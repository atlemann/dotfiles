;;; magit-glab-data.el --- Merge requests, cached, and the commits they are -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; GitLab's JSON turned into the few records the user interface needs --
;; `magit-glab-mr', `magit-glab-discussion', `magit-glab-note',
;; `magit-glab-patchset' -- kept in a cache, and connected to local
;; commits.  The interface never calls the API itself: it asks this
;; library, gets what is cached at once, and is told when fresher data
;; arrives (`magit-glab-subscribe').  So no buffer refresh ever waits on
;; the network.
;;
;; A merge request is known by its key, (PROJECT . IID), PROJECT being the
;; full path such as "ds365ai/resoptima/irma".
;;
;; The join between a commit and its merge request is push-stack's: the
;; commit's Change-Id trailer names the branch change/<Change-Id>, which
;; is the source branch of the merge request.
;;
;; Summaries -- everything the dashboard and status section show -- come
;; from one GraphQL query for all of the user's merge requests.  A merge
;; request's buffer needs more: its description, discussions, versions and
;; draft notes, which `magit-glab-refresh-mr' fetches with four requests in
;; parallel.
;;
;; A little state survives restarts, in `magit-glab-state-file': which
;; notes and versions of each merge request were seen, and where each
;; project is checked out.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-api)

(defcustom magit-glab-remote "origin"
  "The remote whose URL names a repository's GitLab project."
  :group 'magit-glab
  :type 'string)

(defcustom magit-glab-stack-base nil
  "The branch of `magit-glab-remote' a stack of commits is on.
nil means `magit-push-stack-default-base' when that is defined, or
\"master\"."
  :group 'magit-glab
  :type '(choice (const :tag "push-stack's default" nil) string))

(defcustom magit-glab-max-age 60
  "Seconds cached data is used before it is fetched again."
  :group 'magit-glab
  :type 'natnum)

(defcustom magit-glab-project-directories nil
  "Where GitLab projects are checked out, as (PROJECT . DIRECTORY).
Projects seen in Magit are remembered by themselves; this is for
the others, or to override what was remembered."
  :group 'magit-glab
  :type '(alist :key-type string :value-type directory))

(defcustom magit-glab-submit-label "submit"
  "The label that has the submit bot land a stack.
On the highest merge request to land, it lands that one and every one
below it on the main branch in one push: Gerrit's \"submit including
parents\"."
  :group 'magit-glab
  :type 'string)

(defcustom magit-glab-state-file (locate-user-emacs-file "magit-glab-state.eld")
  "File keeping what was seen of each merge request, and checkouts."
  :group 'magit-glab
  :type 'file)

;;;; Records

(cl-defstruct (magit-glab-mr (:constructor magit-glab-mr--create)
                             (:copier nil))
  "A merge request.  The slots after `assignees' are filled in only by
`magit-glab-refresh-mr', which sets `full-p'."
  project iid title draft state author web-url source-branch target-branch
  head-sha updated-at merge-status pipeline-status pipeline-id approved-by
  approvals-left approved resolvable-count resolved-count notes-count
  reviewers assignees labels conflicts threads-blocking
  description diff-refs discussions patchsets drafts full-p)

(defconst magit-glab--summary-slots
  '(title draft state author web-url source-branch target-branch head-sha
          updated-at merge-status pipeline-status pipeline-id approved-by
          approvals-left approved resolvable-count resolved-count notes-count
          reviewers assignees labels conflicts threads-blocking)
  "The `magit-glab-mr' slots a summary has.")

(cl-defstruct (magit-glab-discussion (:constructor magit-glab-discussion--create)
                                     (:copier nil))
  "A thread, or a single comment (INDIVIDUAL)."
  id individual notes)

(cl-defstruct (magit-glab-note (:constructor magit-glab-note--create)
                               (:copier nil))
  id discussion-id author body created updated system resolvable resolved
  resolved-by position)

(cl-defstruct (magit-glab-patchset (:constructor magit-glab-patchset--create)
                                   (:copier nil))
  "A version of a merge request with a head of its own, numbered from 1.
LOCAL is non-nil for a local commit newer than any pushed version."
  number head base start created version-id local)

(cl-defstruct (magit-glab-draft (:constructor magit-glab-draft--create)
                                (:copier nil))
  "An unpublished note of the current user."
  id body discussion-id position resolve)

(defun magit-glab-mr-key (mr)
  "Return MR's key, (PROJECT . IID)."
  (cons (magit-glab-mr-project mr) (magit-glab-mr-iid mr)))

(defun magit-glab-mr-change-id (mr)
  "Return the Change-Id in MR's source branch, if it is a push-stack one."
  (let ((branch (magit-glab-mr-source-branch mr)))
    (and branch (string-prefix-p "change/" branch)
         (substring branch (length "change/")))))

(defun magit-glab-mr-mine-p (mr)
  "Return non-nil if the current user wrote MR."
  (equal (magit-glab-mr-author mr) (magit-glab-username)))

(defun magit-glab-mr-reviewer (mr &optional username)
  "Return the reviewer plist of USERNAME (default: me) on MR, if any."
  (let ((username (or username (magit-glab-username))))
    (seq-find (lambda (reviewer) (equal (plist-get reviewer :username) username))
              (magit-glab-mr-reviewers mr))))

(defun magit-glab-mr-stacked-p (mr)
  "Return non-nil if MR targets the branch of another merge request.
Such a merge request lands by `magit-glab-submit-label', never by
GitLab's Merge button, which would merge it into that branch."
  (string-prefix-p "change/" (or (magit-glab-mr-target-branch mr) "")))

(defun magit-glab-mr-submit-p (mr)
  "Return non-nil if MR has `magit-glab-submit-label'."
  (member magit-glab-submit-label (magit-glab-mr-labels mr)))

(defun magit-glab-mr-below (mr)
  "Return the cached open merge request whose branch MR targets, or nil."
  (when (magit-glab-mr-stacked-p mr)
    (let ((below (magit-glab-mr-for-change-id
                  (magit-glab-mr-project mr)
                  (substring (magit-glab-mr-target-branch mr) (length "change/")))))
      (and below (equal (magit-glab-mr-state below) "opened") below))))

(defun magit-glab-mr-chain (mr)
  "Return MR and the cached merge requests below it, lowest first.
The chain stops at one that targets no merge request, or whose target
the cache does not know: then its first one is still stacked."
  (let ((chain (list mr))
        below)
    (while (and (setq below (magit-glab-mr-below (car chain)))
                (not (memq below chain)))
      (push below chain))
    chain))

(defun magit-glab-mr-open-threads (mr)
  "Return how many of MR's resolvable threads are unresolved."
  (- (or (magit-glab-mr-resolvable-count mr) 0)
     (or (magit-glab-mr-resolved-count mr) 0)))

(defun magit-glab-discussion-first (discussion)
  "Return DISCUSSION's first note."
  (car (magit-glab-discussion-notes discussion)))

(defun magit-glab-discussion-position (discussion)
  "Return the diff position of DISCUSSION, nil if it is not inline."
  (magit-glab-note-position (magit-glab-discussion-first discussion)))

(defun magit-glab-discussion-resolvable (discussion)
  "Return non-nil if DISCUSSION can be resolved."
  (seq-some #'magit-glab-note-resolvable (magit-glab-discussion-notes discussion)))

(defun magit-glab-discussion-resolved (discussion)
  "Return non-nil if DISCUSSION is resolvable and resolved."
  (let ((notes (seq-filter #'magit-glab-note-resolvable
                           (magit-glab-discussion-notes discussion))))
    (and notes (seq-every-p #'magit-glab-note-resolved notes))))

(defun magit-glab-discussion-system-p (discussion)
  "Return non-nil if DISCUSSION is GitLab's own activity, not a comment."
  (seq-every-p #'magit-glab-note-system (magit-glab-discussion-notes discussion)))

;;;; From JSON

(defun magit-glab--nodes (connection)
  "Return the nodes of a GraphQL CONNECTION."
  (alist-get 'nodes connection))

(defun magit-glab--gid-number (gid)
  "Return the number at the end of GraphQL global id GID."
  (and gid (string-match "/\\([0-9]+\\)\\'" gid)
       (string-to-number (match-string 1 gid))))

(defconst magit-glab--mr-fragment
  "fragment MR on MergeRequest {
  iid title draft state webUrl sourceBranch targetBranch updatedAt
  detailedMergeStatus diffHeadSha userNotesCount
  project { fullPath } author { username }
  headPipeline { id status }
  approvedBy { nodes { username } } approvalsLeft approved
  resolvableDiscussionsCount resolvedDiscussionsCount
  reviewers { nodes { username mergeRequestInteraction { reviewState approved } } }
  assignees { nodes { username } }
  labels { nodes { title } }
  conflicts mergeableDiscussionsState
}"
  "The GraphQL fields of a merge request summary.")

(defun magit-glab--mr-from-graphql (node)
  "Return a `magit-glab-mr' from the GraphQL merge request NODE."
  (let-alist node
    (magit-glab-mr--create
     :project .project.fullPath
     :iid (if (stringp .iid) (string-to-number .iid) .iid)
     :title .title :draft .draft :state .state :web-url .webUrl
     :author .author.username
     :source-branch .sourceBranch :target-branch .targetBranch
     :head-sha .diffHeadSha :updated-at .updatedAt
     :merge-status (and .detailedMergeStatus (downcase .detailedMergeStatus))
     :pipeline-status (and .headPipeline.status (downcase .headPipeline.status))
     :pipeline-id (magit-glab--gid-number .headPipeline.id)
     :approved-by (mapcar (lambda (user) (alist-get 'username user))
                          (magit-glab--nodes .approvedBy))
     :approvals-left .approvalsLeft :approved .approved
     :resolvable-count .resolvableDiscussionsCount
     :resolved-count .resolvedDiscussionsCount
     :notes-count .userNotesCount
     :reviewers (mapcar (lambda (reviewer)
                          (let-alist reviewer
                            (list :username .username
                                  :state (and .mergeRequestInteraction.reviewState
                                              (downcase
                                               .mergeRequestInteraction.reviewState))
                                  :approved .mergeRequestInteraction.approved)))
                        (magit-glab--nodes .reviewers))
     :assignees (mapcar (lambda (user) (alist-get 'username user))
                        (magit-glab--nodes .assignees))
     :labels (mapcar (lambda (label) (alist-get 'title label))
                     (magit-glab--nodes .labels))
     :conflicts .conflicts
     ;; False comes as nil, so only a node that has the field can say no.
     :threads-blocking (and (assq 'mergeableDiscussionsState node)
                            (not .mergeableDiscussionsState))
     :description .description
     :diff-refs (and .diffRefs
                     (list :base .diffRefs.baseSha :head .diffRefs.headSha
                           :start .diffRefs.startSha)))))

(defun magit-glab--position-from-rest (position)
  "Return a position plist from a REST note's POSITION."
  (when position
    (let-alist position
      (list :base .base_sha :start .start_sha :head .head_sha
            :old-path .old_path :new-path .new_path
            :old-line .old_line :new-line .new_line))))

(defun magit-glab--note-from-rest (note discussion-id)
  "Return a `magit-glab-note' from a REST NOTE of DISCUSSION-ID."
  (let-alist note
    (magit-glab-note--create
     :id .id :discussion-id discussion-id :author .author.username
     :body (or .body "") :created .created_at :updated .updated_at
     :system .system :resolvable .resolvable :resolved .resolved
     :resolved-by .resolved_by.username
     :position (and (equal .type "DiffNote")
                    (magit-glab--position-from-rest .position)))))

(defun magit-glab--discussion-from-rest (discussion)
  "Return a `magit-glab-discussion' from a REST DISCUSSION."
  (let-alist discussion
    (magit-glab-discussion--create
     :id .id :individual .individual_note
     :notes (mapcar (lambda (note) (magit-glab--note-from-rest note .id))
                    .notes))))

(defun magit-glab--draft-from-rest (draft)
  "Return a `magit-glab-draft' from a REST draft note DRAFT."
  (let-alist draft
    (magit-glab-draft--create
     :id .id :body (or .note "") :discussion-id .discussion_id
     :resolve .resolve_discussion
     :position (and .position (alist-get 'new_path .position)
                    (magit-glab--position-from-rest .position)))))

(defun magit-glab--patchsets (versions)
  "Return the patchsets in VERSIONS, GitLab's list of an MR's versions.
GitLab lists the newest version first, and adds a version whenever the
target branch moves -- in a stack, whenever the merge request below is
amended -- so many versions share a head commit.  A patchset is a head
commit, numbered in the order the heads first appeared; its base and
start are those of that first version."
  (let ((seen (make-hash-table :test #'equal))
        (number 0)
        patchsets)
    (dolist (version (reverse versions))
      (let-alist version
        (unless (gethash .head_commit_sha seen)
          (puthash .head_commit_sha t seen)
          (push (magit-glab-patchset--create
                 :number (cl-incf number) :head .head_commit_sha
                 :base .base_commit_sha :start .start_commit_sha
                 :created .created_at :version-id .id)
                patchsets))))
    (nreverse patchsets)))

;;;; Cache

(defvar magit-glab--mrs (make-hash-table :test #'equal)
  "Merge requests by key, (PROJECT . IID).")

(defvar magit-glab--fetch-times (make-hash-table :test #'equal)
  "When each cache key was last fetched, as a float time.")

(defvar magit-glab--inflight (make-hash-table :test #'equal)
  "Cache keys being fetched, with the callbacks waiting for them.")

(defvar magit-glab--dashboard nil
  "The user's merge requests: a plist of :authored, :review and :assigned,
each a list of keys, and :todos, a list of to-do plists.")

(defvar magit-glab--patch-ids (make-hash-table :test #'equal)
  "Patch ids of MR versions by version id.  Versions never change.")

(defun magit-glab-get-mr (key)
  "Return the cached merge request KEY, or nil."
  (gethash key magit-glab--mrs))

(defun magit-glab--store (mr)
  "Put MR in the cache and return what is cached for it.
A summary updates the summary fields of a cached full merge request,
keeping its discussions."
  (let* ((key (magit-glab-mr-key mr))
         (old (gethash key magit-glab--mrs)))
    (if (and old (magit-glab-mr-full-p old) (not (magit-glab-mr-full-p mr)))
        (progn
          (dolist (slot magit-glab--summary-slots)
            (setf (cl-struct-slot-value 'magit-glab-mr slot old)
                  (cl-struct-slot-value 'magit-glab-mr slot mr)))
          old)
      (puthash key mr magit-glab--mrs))))

(defun magit-glab-stale-p (key &optional max-age)
  "Return non-nil if KEY was not fetched in the last MAX-AGE seconds.
MAX-AGE defaults to `magit-glab-max-age'."
  (let ((time (gethash key magit-glab--fetch-times)))
    (or (not time)
        (> (- (float-time) time) (or max-age magit-glab-max-age)))))

(defun magit-glab-fetching-p (key)
  "Return non-nil if KEY is being fetched."
  (gethash key magit-glab--inflight))

(defun magit-glab--fetch (key fetcher callback)
  "Run FETCHER for KEY, unless it already runs; then call CALLBACK.
FETCHER is called with a function to call when done, with non-nil for
success.  CALLBACK, if non-nil, gets that same flag.  A failure counts
as a fetch too, so a broken request is not retried at every refresh."
  (if-let* ((waiting (gethash key magit-glab--inflight)))
      (puthash key (cons callback waiting) magit-glab--inflight)
    (puthash key (list callback) magit-glab--inflight)
    (funcall fetcher
             (lambda (ok)
               (let ((callbacks (gethash key magit-glab--inflight)))
                 (remhash key magit-glab--inflight)
                 (puthash key (float-time) magit-glab--fetch-times)
                 (magit-glab--changed key)
                 (dolist (callback callbacks)
                   (when callback
                     (magit-glab--call callback ok))))))))

;;;; Telling buffers

(defvar magit-glab--subscribers nil
  "Buffers to tell about new data, as (BUFFER . FUNCTION).")

(defun magit-glab-subscribe (function)
  "Call FUNCTION in this buffer with each cache key that is fetched anew."
  (setq magit-glab--subscribers
        (cons (cons (current-buffer) function)
              (seq-remove (lambda (entry)
                            (or (eq (car entry) (current-buffer))
                                (not (buffer-live-p (car entry)))))
                          magit-glab--subscribers))))

(defun magit-glab--changed (key)
  "Tell the subscribed buffers that KEY was fetched."
  (dolist (entry magit-glab--subscribers)
    (when (buffer-live-p (car entry))
      (with-current-buffer (car entry)
        (magit-glab--call (cdr entry) key)))))

(defvar-local magit-glab--refresh-timer nil)

(defun magit-glab-refresh-soon (&optional buffer function)
  "Refresh BUFFER (default: this one) shortly, once, with FUNCTION.
FUNCTION defaults to `magit-refresh-buffer'.  Several fetches landing
together cause one refresh."
  (let ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (unless magit-glab--refresh-timer
        (setq magit-glab--refresh-timer
              (run-with-timer
               0.2 nil
               (lambda ()
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (setq magit-glab--refresh-timer nil)
                     (let ((window (get-buffer-window buffer t)))
                       (if window
                           (with-selected-window window
                             (save-excursion
                               (funcall (or function #'magit-refresh-buffer))))
                         (funcall (or function #'magit-refresh-buffer)))))))))))))

;;;; Fetching a merge request

(defun magit-glab--mr-endpoint (key &optional suffix)
  "Return the REST endpoint of merge request KEY, with SUFFIX."
  (format "projects/%s/merge_requests/%d%s"
          (magit-glab-encode (car key)) (cdr key) (or suffix "")))

(defun magit-glab-refresh-mr (key &optional callback)
  "Fetch everything about the merge request KEY; then call CALLBACK.
CALLBACK gets non-nil when it all arrived."
  (magit-glab--fetch key (lambda (done) (magit-glab--fetch-mr key done)) callback))

(defun magit-glab-ensure-mr (key &optional max-age)
  "Return the cached full merge request KEY, fetching it if stale.
The fetch runs in the background; subscribers hear when it is done."
  (let ((mr (magit-glab-get-mr key)))
    (when (or (not (and mr (magit-glab-mr-full-p mr)))
              (magit-glab-stale-p key max-age))
      (unless (magit-glab-fetching-p key)
        (magit-glab-refresh-mr key)))
    mr))

(defun magit-glab--fetch-mr (key done)
  "Fetch merge request KEY's summary, discussions, versions and drafts.
Call DONE with non-nil if all four arrived."
  (let ((pending 4) (ok t) node discussions versions drafts)
    (cl-flet ((finish ()
                (when (zerop (cl-decf pending))
                  (if (not node)
                      (funcall done nil)
                    (let ((mr (magit-glab--mr-from-graphql node)))
                      (setf (magit-glab-mr-discussions mr)
                            (mapcar #'magit-glab--discussion-from-rest discussions)
                            (magit-glab-mr-patchsets mr)
                            (magit-glab--patchsets versions)
                            (magit-glab-mr-drafts mr)
                            (mapcar #'magit-glab--draft-from-rest drafts)
                            (magit-glab-mr-full-p mr) ok)
                      (magit-glab--store mr)
                      (funcall done ok)))))
              (failed (message)
                (setq ok nil)
                (magit-glab-default-errback message)))
      (magit-glab-graphql
       (concat magit-glab--mr-fragment "
query($project: ID!, $iid: String!) {
  project(fullPath: $project) {
    mergeRequest(iid: $iid) { ...MR description diffRefs { baseSha headSha startSha } }
  }
}")
       :variables `((project . ,(car key)) (iid . ,(number-to-string (cdr key))))
       :callback (lambda (data)
                   (setq node (let-alist data .project.mergeRequest))
                   (unless node
                     (failed (format "no merge request !%d in %s" (cdr key) (car key))))
                   (finish))
       :errback (lambda (message) (failed message) (finish)))
      (dolist (part `(("/discussions" . ,(lambda (items) (setq discussions items)))
                      ("/versions" . ,(lambda (items) (setq versions items)))
                      ("/draft_notes" . ,(lambda (items) (setq drafts items)))))
        (magit-glab-api (magit-glab--mr-endpoint key (car part))
                        :params '((per_page . 100))
                        :paginate t
                        :callback (let ((setter (cdr part)))
                                    (lambda (items) (funcall setter items) (finish)))
                        :errback (lambda (message) (failed message) (finish)))))))

;;;; Fetching the dashboard

(defun magit-glab-refresh-dashboard (&optional callback)
  "Fetch the user's merge requests and to-dos; then call CALLBACK."
  (magit-glab--fetch 'dashboard #'magit-glab--fetch-dashboard callback))

(defun magit-glab-ensure-dashboard (&optional max-age)
  "Return the cached dashboard plist, fetching it if stale."
  (when (and (magit-glab-stale-p 'dashboard max-age)
             (not (magit-glab-fetching-p 'dashboard)))
    (magit-glab-refresh-dashboard))
  magit-glab--dashboard)

(defun magit-glab--todo-from-rest (todo)
  "Return a to-do plist from a REST TODO."
  (let-alist todo
    (list :id .id :action .action_name :author .author.username
          :body .body :project .project.path_with_namespace
          :iid .target.iid :title .target.title :created .created_at)))

(defconst magit-glab--dashboard-lists
  '((:authored . "authoredMergeRequests")
    (:review . "reviewRequestedMergeRequests")
    (:assigned . "assignedMergeRequests"))
  "The dashboard's lists, and the `currentUser' field each comes from.
One query each: all three in one exceeds gitlab.com's complexity limit.")

(defun magit-glab--fetch-dashboard (done)
  "Fetch the authored, review-requested and assigned merge requests.
Call DONE with non-nil for success.  A list that fails keeps what it had."
  (let ((pending (1+ (length magit-glab--dashboard-lists)))
        (ok t)
        (dashboard (copy-sequence magit-glab--dashboard)))
    (cl-flet ((finish ()
                (when (zerop (cl-decf pending))
                  (setq magit-glab--dashboard (plist-put dashboard :time (float-time)))
                  (funcall done ok)))
              (failed (message)
                (setq ok nil)
                (magit-glab-default-errback message)))
      (pcase-dolist (`(,list . ,field) magit-glab--dashboard-lists)
        (magit-glab-graphql
         (format "%s
query { currentUser { %s(state: opened, first: 100) { nodes { ...MR } } } }"
                 magit-glab--mr-fragment field)
         :callback (lambda (data)
                     (setq dashboard
                           (plist-put dashboard list
                                      (mapcar (lambda (node)
                                                (magit-glab-mr-key
                                                 (magit-glab--store
                                                  (magit-glab--mr-from-graphql node))))
                                              (magit-glab--nodes
                                               (alist-get (intern field)
                                                          (alist-get 'currentUser data))))))
                     (finish))
         :errback (lambda (message) (failed message) (finish))))
      (magit-glab-api "todos"
                      :params '((state . "pending") (type . "MergeRequest")
                                (per_page . 100))
                      :callback (lambda (items)
                                  (setq dashboard
                                        (plist-put dashboard :todos
                                                   (mapcar #'magit-glab--todo-from-rest items)))
                                  (finish))
                      :errback (lambda (message) (failed message) (finish))))))

(defun magit-glab-dashboard-mrs (list)
  "Return the cached merge requests of dashboard LIST.
LIST is :authored, :review or :assigned."
  (delq nil (mapcar #'magit-glab-get-mr (plist-get magit-glab--dashboard list))))

;;;; Looking up a Change-Id

(defvar magit-glab--looked-up (make-hash-table :test #'equal)
  "Change-Ids asked of GitLab, so each is asked once a session.")

(defun magit-glab-lookup-change-id (project change-id)
  "Ask GitLab for PROJECT's merge requests of CHANGE-ID, in the background.
For commits of merge requests that are not the user's, so not in the
dashboard.  Subscribers hear of it as the key (change-id . CHANGE-ID)."
  (let ((key (cons 'change-id change-id)))
    (unless (or (gethash key magit-glab--looked-up) (magit-glab-fetching-p key))
      (puthash key t magit-glab--looked-up)
      (magit-glab--fetch
       key
       (lambda (done)
         (magit-glab-graphql
          (concat magit-glab--mr-fragment "
query($project: ID!, $branch: String!) {
  project(fullPath: $project) {
    mergeRequests(sourceBranches: [$branch], first: 10) { nodes { ...MR } }
  }
}")
          :variables `((project . ,project) (branch . ,(concat "change/" change-id)))
          :callback (lambda (data)
                      (dolist (node (magit-glab--nodes
                                     (let-alist data .project.mergeRequests)))
                        (magit-glab--store (magit-glab--mr-from-graphql node)))
                      (funcall done t))
          :errback (lambda (message)
                     (magit-glab-default-errback message)
                     (funcall done nil))))
       nil))))

;;;; Patch ids

(defun magit-glab-patch-id (key patchset)
  "Return the patch id of PATCHSET of merge request KEY, if known.
If not, ask GitLab for it in the background; subscribers hear of it as
the key (patch-id . VERSION-ID)."
  (let ((id (magit-glab-patchset-version-id patchset)))
    (or (gethash id magit-glab--patch-ids)
        (progn
          (when (and id (not (magit-glab-fetching-p (cons 'patch-id id))))
            (magit-glab--fetch
             (cons 'patch-id id)
             (lambda (done)
               (magit-glab-api (magit-glab--mr-endpoint key (format "/versions/%s" id))
                               :callback (lambda (version)
                                           (puthash id (alist-get 'patch_id_sha version)
                                                    magit-glab--patch-ids)
                                           (funcall done t))
                               :errback (lambda (_) (funcall done nil))))
             nil))
          nil))))

;;;; Projects and directories

(defvar magit-glab--projects (make-hash-table :test #'equal)
  "The GitLab project of each directory, or `none'.")

(defun magit-glab-parse-remote-url (url)
  "Return the GitLab project path in remote URL, or nil."
  (let ((host (regexp-quote magit-glab-host)))
    (cond ((string-match (concat "\\`\\(?:ssh://\\)?git@" host
                                 "[:/]\\(.+?\\)\\(?:\\.git\\)?/?\\'")
                         url)
           (match-string 1 url))
          ((string-match (concat "\\`https?://\\(?:[^@/]+@\\)?" host
                                 "/\\(.+?\\)\\(?:\\.git\\)?/?\\'")
                         url)
           (match-string 1 url)))))

(defun magit-glab-project (&optional directory)
  "Return the GitLab project of the repository DIRECTORY is in, or nil.
DIRECTORY defaults to `default-directory'.  Asked of git once per
directory."
  (let* ((default-directory (or directory default-directory))
         (project (gethash default-directory magit-glab--projects 'unknown)))
    (when (eq project 'unknown)
      (setq project (or (and (magit-toplevel)
                             (magit-glab-parse-remote-url
                              (or (magit-get "remote" magit-glab-remote "url") "")))
                        'none))
      (puthash default-directory project magit-glab--projects)
      (when (stringp project)
        (magit-glab--remember-directory project)))
    (and (stringp project) project)))

(defun magit-glab--main-worktree ()
  "Return the top of the main worktree of the repository here."
  (let ((common (magit-git-string "rev-parse" "--path-format=absolute"
                                  "--git-common-dir")))
    (if (and common (string-suffix-p "/.git" common))
        (concat (or (file-remote-p default-directory) "")
                (file-name-as-directory (file-name-directory common)))
      (magit-toplevel))))

(defun magit-glab--remember-directory (project)
  "Remember the repository here as where PROJECT is checked out."
  (unless (assoc project (magit-glab--state-get :dirs))
    (when-let* ((main (magit-glab--main-worktree)))
      (magit-glab--state-put :dirs (cons (cons project main)
                                         (magit-glab--state-get :dirs))))))

(defun magit-glab-project-directory (project &optional ask)
  "Return where PROJECT is checked out, or nil.
With ASK, ask for it when not known, and remember the answer."
  (or (and (equal (magit-glab-project) project) (magit-toplevel))
      (alist-get project magit-glab-project-directories nil nil #'equal)
      (alist-get project (magit-glab--state-get :dirs) nil nil #'equal)
      (and ask
           (let ((directory (file-name-as-directory
                             (read-directory-name
                              (format "Where is %s checked out? " project)))))
             (let ((default-directory directory))
               (unless (equal (magit-glab-project) project)
                 (user-error "%s is not a checkout of %s" directory project)))
             directory))))

;;;; Stacks: commits and their merge requests

(defun magit-glab-stack-base ()
  "Return the remote branch a stack is on, such as \"origin/master\"."
  (format "%s/%s" magit-glab-remote
          (or magit-glab-stack-base
              (bound-and-true-p magit-push-stack-default-base)
              "master")))

(defun magit-glab-parse-log (output)
  "Parse OUTPUT of `magit-glab-stack-commits's git log.
Return a list of plists (:sha :subject :change-id)."
  (delq nil
        (mapcar (lambda (record)
                  (let ((fields (split-string (string-trim record "[\n]+" "[\n]+")
                                              "\x1f")))
                    (when (>= (length fields) 2)
                      (list :sha (nth 0 fields)
                            :subject (nth 1 fields)
                            :change-id (car (split-string (or (nth 2 fields) "")
                                                          "[\x1d\n]" t "[ \t]+"))))))
                (split-string output "\x1e" t "[\n]+"))))

(defun magit-glab-stack-commits (&optional tip)
  "Return the commits from the stack base to TIP (default HEAD), oldest first.
Each is a plist (:sha :subject :change-id).  One git call."
  (magit-glab-parse-log
   (magit-git-output "log" "--reverse" "--max-count=50"
                     "--format=%H%x1f%s%x1f%(trailers:key=Change-Id,valueonly,separator=%x1d)%x1e"
                     (concat (magit-glab-stack-base) ".." (or tip "HEAD")))))

(defun magit-glab-change-id (rev)
  "Return the Change-Id trailer of REV, or nil."
  (when-let* ((value (magit-git-string
                      "log" "-1"
                      "--format=%(trailers:key=Change-Id,valueonly,separator=%x1d)"
                      rev)))
    (car (split-string value "[\x1d\n]" t "[ \t]+"))))

(defun magit-glab-mr-for-change-id (project change-id)
  "Return the cached merge request of PROJECT for CHANGE-ID, or nil.
An open one if there is one, else the most recently updated."
  (when change-id
    (let ((branch (concat "change/" change-id))
          found)
      (maphash (lambda (key mr)
                 (when (and (equal (car key) project)
                            (equal (magit-glab-mr-source-branch mr) branch)
                            (or (not found)
                                (and (equal (magit-glab-mr-state mr) "opened")
                                     (not (equal (magit-glab-mr-state found) "opened")))
                                (string> (or (magit-glab-mr-updated-at mr) "")
                                         (or (magit-glab-mr-updated-at found) ""))))
                   (setq found mr)))
               magit-glab--mrs)
      found)))

(defun magit-glab-mr-trees (mrs)
  "Arrange MRS into stacks: return a list of trees (MR . CHILDREN).
A merge request is a child of the one whose source branch it targets.
Roots, and children, keep the order they have in MRS -- except that
roots are ordered by their newest member, most recent first."
  (let ((by-branch (make-hash-table :test #'equal))
        (children (make-hash-table :test #'eq))
        roots)
    (dolist (mr mrs)
      (puthash (cons (magit-glab-mr-project mr) (magit-glab-mr-source-branch mr))
               mr by-branch))
    (dolist (mr mrs)
      (let ((parent (gethash (cons (magit-glab-mr-project mr)
                                   (magit-glab-mr-target-branch mr))
                             by-branch)))
        (if (and parent (not (eq parent mr)))
            (push mr (gethash parent children))
          (push mr roots))))
    (cl-labels ((tree (mr) (cons mr (mapcar #'tree (reverse (gethash mr children)))))
                (members (tree) (cons (car tree) (mapcan #'members (cdr tree))))
                ;; ISO 8601 times in the same zone sort as strings.
                (newest (tree) (car (sort (mapcar (lambda (mr)
                                                    (or (magit-glab-mr-updated-at mr) ""))
                                                  (members tree))
                                          :reverse t))))
      (sort (mapcar #'tree (nreverse roots))
            :key #'newest :lessp #'string< :reverse t))))

;;;; State kept across sessions

(defvar magit-glab--state 'unloaded
  "A plist: :seen, a hash table from \"PROJECT!IID\" to a plist of what
was seen (:note :count :head), and :dirs, an alist from project to
directory.")

(defun magit-glab--state ()
  "Return the state, reading `magit-glab-state-file' the first time."
  (when (eq magit-glab--state 'unloaded)
    (setq magit-glab--state
          (or (ignore-errors
                (with-temp-buffer
                  (insert-file-contents magit-glab-state-file)
                  (read (current-buffer))))
              (list :seen (make-hash-table :test #'equal) :dirs nil))))
  magit-glab--state)

(defun magit-glab--state-get (property)
  "Return PROPERTY of the saved state."
  (plist-get (magit-glab--state) property))

(defun magit-glab--state-put (property value)
  "Set PROPERTY of the saved state to VALUE, and save it."
  (setq magit-glab--state (plist-put (magit-glab--state) property value))
  (magit-glab--state-save))

(defun magit-glab--state-save ()
  "Write the state to `magit-glab-state-file'."
  (let ((print-length nil) (print-level nil))
    (with-temp-file magit-glab-state-file
      (insert ";; magit-glab's state -*- lisp-data -*-\n")
      (prin1 magit-glab--state (current-buffer))
      (insert "\n"))))

(defun magit-glab--seen-key (key)
  "Return the state's key for merge request KEY."
  (format "%s!%d" (car key) (cdr key)))

(defun magit-glab-seen (key)
  "Return what was seen of merge request KEY: a plist (:note :count :head)."
  (gethash (magit-glab--seen-key key) (magit-glab--state-get :seen)))

(defun magit-glab-mark-seen (key &rest properties)
  "Record PROPERTIES as seen of merge request KEY, and save."
  (let* ((seen (magit-glab--state-get :seen))
         (old (gethash (magit-glab--seen-key key) seen))
         (new (copy-sequence old)))
    (cl-loop for (property value) on properties by #'cddr
             do (setq new (plist-put new property value)))
    (unless (equal old new)
      (puthash (magit-glab--seen-key key) new seen)
      (magit-glab--state-save))))

(defun magit-glab-new-notes-count (mr)
  "Return how many notes MR has gained since it was last opened, or nil.
nil when it was never opened."
  (when-let* ((seen (magit-glab-seen (magit-glab-mr-key mr)))
              (count (plist-get seen :count)))
    (max 0 (- (or (magit-glab-mr-notes-count mr) 0) count))))

(provide 'magit-glab-data)
;;; magit-glab-data.el ends here
