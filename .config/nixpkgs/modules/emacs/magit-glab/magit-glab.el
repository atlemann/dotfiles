;;; magit-glab.el --- GitLab merge request review in Magit, on glab -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0") (transient "0.5"))
;; Keywords: vc, tools

;;; Commentary:
;; Review GitLab merge requests from Magit, the way Gerrit changes were
;; reviewed: with push-stack, every commit is a merge request, and its
;; Change-Id ties the two together.  Everything goes through the glab CLI
;; -- run on this machine, also for repositories on another one over
;; TRAMP -- so `glab auth login' is all the setup GitLab needs.
;;
;; Entry points:
;;
;;   `magit-glab-dashboard'   your merge requests, those to review, to-dos
;;   `magit-glab-dispatch'    @ in Magit buffers: everything below
;;   `magit-glab-mr-visit'    one merge request: threads, patchsets, ...
;;
;; And in Magit's own buffers, once `magit-glab-setup' has run:
;;
;;   - the status buffer lists the stack's commits with their merge
;;     requests (approvals, pipeline, open threads); RET on one shows the
;;     commit
;;   - a commit's revision buffer says which merge request and patchset it
;;     is, and shows the review threads under their lines
;;   - `magit-glab-mr-diff' and `magit-glab-diff-patchsets' diffs do too
;;
;; `magit-glab-land' lands a merge request as irma does: one that targets
;; master merges; one higher in a stack gets the label "submit", and the
;; submit bot lands it with every one below it.
;;
;; The libraries: magit-glab-api (glab), -data (cache, Change-Ids),
;; -core (shared drawing), -threads (threads in diffs and files),
;; -compose (writing), -versions (patchsets), -worktree, -mr (the merge
;; request buffer), -dashboard, and this one: actions, the status
;; section, the transient and setup.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)
(require 'magit)
(require 'magit-glab-api)
(require 'magit-glab-data)
(require 'magit-glab-core)
(require 'magit-glab-threads)
(require 'magit-glab-compose)
(require 'magit-glab-versions)
(require 'magit-glab-worktree)
(require 'magit-glab-mr)
(require 'magit-glab-dashboard)

(declare-function magit-push-stack "magit-push-stack")

;;;; Browser and URL

;;;###autoload
(defun magit-glab-browse (key)
  "Open merge request KEY in the browser."
  (interactive (list (magit-glab-current-key)))
  (browse-url (or (and (magit-glab-get-mr key) (magit-glab-mr-web-url (magit-glab-get-mr key)))
                  (format "https://%s/%s/-/merge_requests/%d"
                          magit-glab-host (car key) (cdr key)))))

;;;###autoload
(defun magit-glab-copy-url (key &optional with-title)
  "Copy the URL of merge request KEY.
With a prefix argument WITH-TITLE, copy \"!IID title\" and the URL, for
a chat message."
  (interactive (list (magit-glab-current-key) current-prefix-arg))
  (let* ((mr (magit-glab-get-mr key))
         (url (if mr (magit-glab-mr-web-url mr)
                (format "https://%s/%s/-/merge_requests/%d" magit-glab-host (car key) (cdr key)))))
    (kill-new (if (and with-title mr)
                  (format "!%d %s %s" (cdr key) (magit-glab-mr-title mr) url)
                url))
    (message "Copied %s" (car kill-ring))))

;;;; Approving

;;;###autoload
(defun magit-glab-approve (key)
  "Approve merge request KEY."
  (interactive (list (magit-glab-current-key)))
  (let ((mr (magit-glab-get-mr key)))
    (when (or (not mr)
              (zerop (magit-glab-mr-open-threads mr))
              (y-or-n-p (format "!%d has %d open threads; approve anyway? "
                                (cdr key) (magit-glab-mr-open-threads mr))))
      (magit-glab--write key "/approve" "POST" nil
                         (lambda (_) (magit-glab--after-write
                                      key (format "Approved !%d" (cdr key))))))))

;;;###autoload
(defun magit-glab-unapprove (key)
  "Take back your approval of merge request KEY."
  (interactive (list (magit-glab-current-key)))
  (magit-glab--write key "/unapprove" "POST" nil
                     (lambda (_) (magit-glab--after-write
                                  key (format "Unapproved !%d" (cdr key))))))

;;;; Landing

(defun magit-glab--fresh-mr (key)
  "Return merge request KEY as GitLab has it now, and cache it.  Waits."
  (let ((node (let-alist (magit-glab-graphql-sync
                          (concat magit-glab--mr-fragment "
query($project: ID!, $iid: String!) {
  project(fullPath: $project) { mergeRequest(iid: $iid) { ...MR } }
}")
                          `((project . ,(car key)) (iid . ,(number-to-string (cdr key)))))
                .project.mergeRequest)))
    (unless node
      (user-error "No merge request !%d in %s" (cdr key) (car key)))
    (magit-glab--store (magit-glab--mr-from-graphql node))))

(defun magit-glab--fresh-chain (key)
  "Return merge request KEY and every one below it, lowest first.
As GitLab has them now; waits.  The lowest one targets no merge request."
  (let ((chain (list (magit-glab--fresh-mr key))))
    (while (magit-glab-mr-stacked-p (car chain))
      (let* ((mr (car chain))
             (node (car (magit-glab--nodes
                         (let-alist (magit-glab-graphql-sync
                                     (concat magit-glab--mr-fragment "
query($project: ID!, $branch: String!) {
  project(fullPath: $project) {
    mergeRequests(sourceBranches: [$branch], state: opened, first: 1) { nodes { ...MR } }
  }
}")
                                     `((project . ,(magit-glab-mr-project mr))
                                       (branch . ,(magit-glab-mr-target-branch mr))))
                           .project.mergeRequests))))
             (below (and node (magit-glab--store (magit-glab--mr-from-graphql node)))))
        (unless below
          (user-error "!%d targets %s, which has no open merge request: \
fetch, rebase and push-stack first" (magit-glab-mr-iid mr) (magit-glab-mr-target-branch mr)))
        (when (seq-some (lambda (m) (equal (magit-glab-mr-key m) (magit-glab-mr-key below)))
                        chain)
          (user-error "The stack below !%d loops" (cdr key)))
        (push below chain)))
    chain))

(defun magit-glab--set-submit (key on)
  "Put `magit-glab-submit-label' on merge request KEY if ON, else take it off."
  (magit-glab--write key "" "PUT"
                     `((,(if on 'add_labels 'remove_labels) . ,magit-glab-submit-label))
                     (lambda (_)
                       (magit-glab--after-write
                        key (if on
                                (format "Labelled !%d %s; the bot looks once a minute"
                                        (cdr key) magit-glab-submit-label)
                              (format "Took the label %s off !%d"
                                      magit-glab-submit-label (cdr key)))))))

(defun magit-glab--merge (mr)
  "Merge MR into its target branch, as its Merge button would.
Only if its head is still the one checked; squashed if the project
squashes by default."
  (let* ((key (magit-glab-mr-key mr))
         (project (magit-glab-api-sync (format "projects/%s" (magit-glab-encode (car key)))))
         (squash (member (alist-get 'squash_option project) '("always" "default_on"))))
    (when (y-or-n-p (format "Merge !%d into %s? " (cdr key) (magit-glab-mr-target-branch mr)))
      (magit-glab--write key "/merge" "PUT"
                         `((sha . ,(magit-glab-mr-head-sha mr))
                           ,@(and squash '((squash . t))))
                         (lambda (_)
                           (magit-glab--after-write
                            key (format "Merged !%d into %s; fetch and rebase"
                                        (cdr key) (magit-glab-mr-target-branch mr))))))))

;;;###autoload
(defun magit-glab-land (key &optional force)
  "Land merge request KEY on the main branch.
One that targets the main branch merges, as its Merge button would.
One higher in a stack gets `magit-glab-submit-label', and the submit
bot lands it and every merge request below it in one push -- Gerrit's
\"submit including parents\".  The bot does not wait for what is
missing, so this first checks that all of them are ready; with a
prefix argument FORCE, it goes ahead anyway.  On one that has the
label already, offer to take it off."
  (interactive (list (magit-glab-current-key) current-prefix-arg))
  (message "Checking the stack below !%d..." (cdr key))
  (let* ((chain (magit-glab--fresh-chain key))
         (mr (car (last chain)))
         (problems (delq nil (mapcar (lambda (m)
                                       (when-let* ((problem (magit-glab-landing-problem m)))
                                         (format "!%d %s" (magit-glab-mr-iid m) problem)))
                                     chain))))
    (message nil)
    (cond
     ((magit-glab-mr-submit-p mr)
      (when (y-or-n-p (format "!%d has the label %s already; take it off? "
                              (cdr key) magit-glab-submit-label))
        (magit-glab--set-submit key nil)))
     ((and problems (not force))
      (user-error "Not ready to land: %s" (string-join problems ", ")))
     ((not (magit-glab-mr-stacked-p mr))
      (magit-glab--merge mr))
     ((y-or-n-p (format "Label !%d %s, so the bot lands %s on %s? "
                        (cdr key) magit-glab-submit-label (magit-glab-chain-string chain)
                        (magit-glab-mr-target-branch (car chain))))
      (magit-glab--set-submit key t)))))

;;;; Closing

;;;###autoload
(defun magit-glab-toggle-closed (key)
  "Close merge request KEY -- Gerrit's Abandon -- or reopen it.
push-stack does not close the merge request of a commit dropped from
the stack; this does."
  (interactive (list (magit-glab-current-key)))
  (let* ((mr (or (magit-glab-get-mr key) (magit-glab-full-mr key)))
         (closed (equal (magit-glab-mr-state mr) "closed")))
    (when (yes-or-no-p (format "%s !%d %s? " (if closed "Reopen" "Close") (cdr key)
                               (magit-glab-mr-title mr)))
      (magit-glab--write key "" "PUT" `((state_event . ,(if closed "reopen" "close")))
                         (lambda (_) (magit-glab--after-write
                                      key (format "%s !%d" (if closed "Reopened" "Closed")
                                                  (cdr key))))))))

;;;; Draft

(defconst magit-glab--draft-prefix-regexp
  "\\`\\(?:\\[Draft\\]\\|(Draft)\\|Draft:\\|\\[WIP\\]\\|WIP:\\)[ \t]*"
  "What GitLab takes for a draft title prefix.")

;;;###autoload
(defun magit-glab-toggle-draft (key)
  "Mark merge request KEY as draft, or as ready.
By its title's \"Draft: \" prefix, which push-stack keeps when it updates
the title."
  (interactive (list (magit-glab-current-key)))
  (let* ((mr (or (magit-glab-get-mr key) (magit-glab-full-mr key)))
         (title (magit-glab-mr-title mr))
         (new (if (string-match magit-glab--draft-prefix-regexp title)
                  (substring title (match-end 0))
                (concat "Draft: " title))))
    (magit-glab--write key "" "PUT" `((title . ,new))
                       (lambda (_) (magit-glab--after-write
                                    key (format "!%d is %s" (cdr key)
                                                (if (string-prefix-p "Draft: " new)
                                                    "a draft" "ready")))))))

;;;; Reviewers

(defvar magit-glab--members (make-hash-table :test #'equal)
  "Members of each project, as (USERNAME . ID), asked once a session.")

(defun magit-glab-members (project)
  "Return the members of PROJECT as an alist (USERNAME . ID)."
  (with-memoization (gethash project magit-glab--members)
    (message "Fetching the members of %s..." project)
    (mapcar (lambda (member) (cons (alist-get 'username member) (alist-get 'id member)))
            (magit-glab-api-sync (format "projects/%s/members/all" (magit-glab-encode project))
                                 :params '((per_page . 100)) :paginate t))))

(defun magit-glab--set-reviewers (key usernames)
  "Make USERNAMES the reviewers of merge request KEY."
  (let ((members (magit-glab-members (car key))))
    (magit-glab--write
     key "" "PUT"
     `((reviewer_ids . ,(vconcat
                         (mapcar (lambda (username)
                                   (or (cdr (assoc username members))
                                       (user-error "%s is not a member of %s" username (car key))))
                                 usernames))))
     (lambda (_) (magit-glab--after-write
                  key (format "Reviewers of !%d: %s" (cdr key)
                              (if usernames (string-join usernames ", ") "none")))))))

;;;###autoload
(defun magit-glab-rerequest-review (key usernames)
  "Ask USERNAMES, reviewers of merge request KEY, to look at it again.
GitLab's Re-request review, for after answering their comments."
  (interactive
   (let* ((key (magit-glab-current-key))
          (mr (or (magit-glab-get-mr key) (magit-glab-full-mr key)))
          (reviewers (mapcar (lambda (reviewer) (plist-get reviewer :username))
                             (magit-glab-mr-reviewers mr))))
     (list key (cond ((null reviewers) (user-error "!%d has no reviewers" (cdr key)))
                     ((null (cdr reviewers)) reviewers)
                     ((completing-read-multiple "Re-request review from: "
                                                reviewers nil t))))))
  (let ((members (magit-glab-members (car key)))
        (pending (length usernames)))
    (dolist (username usernames)
      (magit-glab-graphql
       "mutation($project: ID!, $iid: String!, $user: UserID!) {
  mergeRequestReviewerRereview(input: {projectPath: $project, iid: $iid, userId: $user}) {
    errors
  }
}"
       :variables `((project . ,(car key)) (iid . ,(number-to-string (cdr key)))
                    (user . ,(format "gid://gitlab/User/%d"
                                     (or (cdr (assoc username members))
                                         (user-error "%s is not a member of %s"
                                                     username (car key))))))
       :callback (lambda (data)
                   (when-let* ((errors (let-alist data .mergeRequestReviewerRereview.errors)))
                     (message "magit-glab: %s: %s" username (string-join errors "; ")))
                   (when (zerop (cl-decf pending))
                     (magit-glab--after-write
                      key (format "Re-requested review of !%d from %s"
                                  (cdr key) (string-join usernames ", ")))))))))

;;;###autoload
(defun magit-glab-add-reviewers (key usernames)
  "Add USERNAMES as reviewers of merge request KEY."
  (interactive
   (let ((key (magit-glab-current-key)))
     (list key (completing-read-multiple
                "Add reviewers: "
                (mapcar #'car (magit-glab-members (car key)))))))
  (let* ((mr (magit-glab-full-mr key))
         (current (mapcar (lambda (r) (plist-get r :username)) (magit-glab-mr-reviewers mr))))
    (magit-glab--set-reviewers key (delete-dups (append current usernames)))))

;;;###autoload
(defun magit-glab-remove-reviewers (key usernames)
  "Remove USERNAMES from the reviewers of merge request KEY."
  (interactive
   (let* ((key (magit-glab-current-key))
          (mr (magit-glab-full-mr key)))
     (list key (completing-read-multiple
                "Remove reviewers: "
                (mapcar (lambda (r) (plist-get r :username)) (magit-glab-mr-reviewers mr))
                nil t))))
  (let* ((mr (magit-glab-full-mr key))
         (current (mapcar (lambda (r) (plist-get r :username)) (magit-glab-mr-reviewers mr))))
    (magit-glab--set-reviewers key (seq-difference current usernames))))

;;;; To-dos

;;;###autoload
(defun magit-glab-todo-done ()
  "Mark the GitLab to-do at point done."
  (interactive)
  (let ((id (get-text-property (line-beginning-position) 'magit-glab-todo)))
    (unless id (user-error "No to-do here"))
    (magit-glab-api (format "todos/%s/mark_as_done" id) :method "POST"
                    :callback (lambda (_)
                                (message "Done")
                                (magit-glab-refresh-dashboard)))))

(defun magit-glab-todos-done (key)
  "Mark the pending to-dos about merge request KEY done."
  (let ((todos (seq-filter (lambda (todo)
                             (and (equal (plist-get todo :project) (car key))
                                  (equal (plist-get todo :iid) (cdr key))))
                           (plist-get magit-glab--dashboard :todos))))
    (when todos
      (let ((pending (length todos)))
        (dolist (todo todos)
          (magit-glab-api (format "todos/%s/mark_as_done" (plist-get todo :id))
                          :method "POST"
                          :callback (lambda (_)
                                      (when (zerop (cl-decf pending))
                                        (magit-glab-refresh-dashboard)))))))))

;;;; Pipeline

(defvar-local magit-glab--pipeline nil
  "The (KEY . PIPELINE-ID) of this pipeline buffer.")

(defvar-local magit-glab--pipeline-jobs nil
  "The jobs this pipeline buffer shows.")

(defvar-local magit-glab--pipeline-checks nil
  "The external checks this pipeline buffer shows.")

(defvar-keymap magit-glab-pipeline-mode-map
  "g"   #'magit-glab-pipeline-refresh
  "q"   #'quit-window
  "RET" #'magit-glab-job-log
  "R"   #'magit-glab-pipeline-retry
  "o"   #'magit-glab-pipeline-browse)

(define-derived-mode magit-glab-pipeline-mode magit-section-mode "GitLab pipeline"
  "The jobs of a merge request's pipeline, and the external checks of its head.

\\{magit-glab-pipeline-mode-map}"
  :interactive nil)

;;;###autoload
(defun magit-glab-pipeline (key)
  "Show the jobs and external checks of merge request KEY's head pipeline."
  (interactive (list (magit-glab-current-key)))
  (let* ((mr (or (magit-glab-get-mr key) (magit-glab-full-mr key)))
         (id (or (magit-glab-mr-pipeline-id mr)
                 (user-error "!%d has no pipeline" (cdr key))))
         (buffer (get-buffer-create (format "*magit-glab-pipeline !%d*" (cdr key)))))
    (with-current-buffer buffer
      (magit-glab-pipeline-mode)
      (setq magit-glab--pipeline (cons key id))
      (magit-glab-pipeline-refresh))
    (pop-to-buffer buffer)))

(defun magit-glab-pipeline-refresh ()
  "Fetch this pipeline's jobs, and its commit's external checks, again.
A pipeline run by CI outside GitLab -- Buildkite, say -- has no jobs on
GitLab, only the statuses the outside CI reported on the commit."
  (interactive nil magit-glab-pipeline-mode)
  (pcase-let* ((`(,key . ,id) magit-glab--pipeline)
               (project (magit-glab-encode (car key)))
               (head (magit-glab-mr-head-sha (magit-glab-get-mr key)))
               (buffer (current-buffer))
               (pending 2)
               (jobs nil)
               (statuses nil))
    (cl-flet ((finish ()
                (when (and (zerop (cl-decf pending)) (buffer-live-p buffer))
                  (with-current-buffer buffer
                    (magit-glab--pipeline-render key id jobs statuses)))))
      (magit-glab-api (format "projects/%s/pipelines/%d/jobs" project id)
                      :params '((per_page . 100)) :paginate t
                      :callback (lambda (items) (setq jobs items) (finish))
                      :errback (lambda (message) (magit-glab-default-errback message) (finish)))
      (if (not head)
          (finish)
        (magit-glab-api (format "projects/%s/repository/commits/%s/statuses" project head)
                        :params '((per_page . 100)) :paginate t
                        :callback (lambda (items) (setq statuses items) (finish))
                        :errback (lambda (message) (magit-glab-default-errback message)
                                   (finish)))))))

(defun magit-glab--status-face (status)
  "Return the face of a job or check STATUS."
  (pcase status
    ("success" 'magit-glab-good)
    ((or "failed" "canceled") 'magit-glab-bad)
    (_ 'magit-glab-open)))

(defun magit-glab--pipeline-render (key id jobs statuses)
  "Show pipeline ID of merge request KEY: its JOBS and external STATUSES."
  (setq magit-glab--pipeline-jobs jobs
        magit-glab--pipeline-checks statuses)
  (magit-glab-with-rerender
    (magit-insert-section (magit-glab-pipeline-root)
      (magit-insert-heading (format "Pipeline %d of !%d" id (cdr key)))
      (when jobs
        (magit-insert-section (magit-glab-jobs)
          (magit-insert-heading "Jobs")
          (dolist (job (sort jobs :key (lambda (job) (alist-get 'id job))))
            (let-alist job
              (magit-insert-section (magit-glab-job .id)
                (magit-insert-heading
                  (format "  %-10s %-10s %-40s %s"
                          (propertize .status 'face (magit-glab--status-face .status))
                          .stage .name
                          (if .duration (format "%ds" (round .duration)) ""))))))
          (insert "\n")))
      (when statuses
        (magit-insert-section (magit-glab-checks)
          (magit-insert-heading "External checks")
          (dolist (status statuses)
            (let-alist status
              (magit-insert-section (magit-glab-check .target_url)
                (magit-insert-heading
                  (format "  %-10s %-30s %s"
                          (propertize .status 'face (magit-glab--status-face .status))
                          .name (or .description ""))))))
          (insert "\n")))
      (unless (or jobs statuses)
        (insert "No jobs or checks on GitLab; o opens the pipeline in the browser.\n")))))

(defun magit-glab-job-log ()
  "Show the log of the job at point, or open the external check at point."
  (interactive nil magit-glab-pipeline-mode)
  (let ((id (magit-section-value-if 'magit-glab-job))
        (url (magit-section-value-if 'magit-glab-check))
        (key (car magit-glab--pipeline)))
    (when url
      (browse-url url))
    (unless (or id url) (user-error "No job or check here"))
    (when id
    (let ((log (magit-glab-api-sync (format "projects/%s/jobs/%d/trace"
                                            (magit-glab-encode (car key)) id)
                                    :raw t))
          (buffer (get-buffer-create (format "*magit-glab-job %d*" id))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert log)
          (ansi-color-apply-on-region (point-min) (point-max))
          (special-mode)
          (goto-char (point-max))))
      (pop-to-buffer buffer)))))

(defun magit-glab-pipeline-retry ()
  "Retry the failed jobs of this pipeline.
A pipeline built outside GitLab has no jobs to retry: then open its
external check -- in Buildkite, Rebuild builds it all again."
  (interactive nil magit-glab-pipeline-mode)
  (pcase-let ((`(,key . ,id) magit-glab--pipeline))
    (if-let* ((check (and (not magit-glab--pipeline-jobs)
                          (seq-find (lambda (status) (alist-get 'target_url status))
                                    magit-glab--pipeline-checks))))
        (progn (browse-url (alist-get 'target_url check))
               (message "Opened %s: rebuild it there" (alist-get 'name check)))
      (magit-glab-api (format "projects/%s/pipelines/%d/retry" (magit-glab-encode (car key)) id)
                      :method "POST"
                      :callback (lambda (_) (message "Retrying pipeline %d" id))))))

(defun magit-glab-pipeline-browse ()
  "Open this pipeline in the browser."
  (interactive nil magit-glab-pipeline-mode)
  (pcase-let ((`(,key . ,id) magit-glab--pipeline))
    (browse-url (format "https://%s/%s/-/pipelines/%d" magit-glab-host (car key) id))))

;;;; The status buffer

(defcustom magit-glab-status-section t
  "Whether the status buffer lists the stack's merge requests."
  :group 'magit-glab
  :type 'boolean)

(defun magit-glab-insert-stack ()
  "Insert the stack's commits with their merge requests.
For `magit-status-sections-hook'.  Only from the cache; a stale cache is
refreshed in the background, and the buffer with it."
  (when-let* ((magit-glab-status-section)
              (project (magit-glab-project))
              (commits (magit-glab-stack-commits)))
    (magit-glab-subscribe #'magit-glab--status-changed)
    (magit-glab-ensure-dashboard)
    (let ((mrs (mapcar (lambda (commit)
                         (magit-glab-mr-for-change-id project (plist-get commit :change-id)))
                       commits))
          (start (point)))
      (magit-insert-section (magit-glab-stack)
        (magit-insert-heading
          (concat (format "Merge requests (%d)" (length commits))
                  (if-let* ((top (magit-glab--landable-top commits mrs)))
                      (propertize (format "  ready to land up to !%d: @ M on it"
                                          (magit-glab-mr-iid top))
                                  'face 'magit-glab-good)
                    "")))
        (cl-loop
         for commit in (reverse commits)
         for mr in (reverse mrs)
         do (let ((sha (plist-get commit :sha)))
              (magit-insert-section (commit sha)
                (magit-insert-heading
                  (concat (propertize (magit-rev-abbrev sha) 'face 'magit-hash) " "
                          (cond
                           ((not (plist-get commit :change-id))
                            (concat (propertize "no Change-Id  " 'face 'magit-glab-bad)
                                    (plist-get commit :subject)))
                           ((not mr)
                            (concat (propertize "not pushed  " 'face 'shadow)
                                    (plist-get commit :subject)))
                           (t
                            (concat (magit-glab-format-mr mr)
                                    (if (equal sha (magit-glab-mr-head-sha mr))
                                        ""
                                      (propertize "  amended, not pushed"
                                                  'face 'magit-glab-new))))))))))
        (insert "\n"))
      (magit-glab-adopt-faces start (point)))))

(defun magit-glab--landable-top (commits mrs)
  "Return the highest merge request of the stack that could land now.
COMMITS are the stack's, oldest first, and MRS their merge requests.
Every one below it must be ready too, and pushed as it is locally."
  (let (top)
    (cl-loop for commit in commits
             for mr in mrs
             while (and mr (equal (plist-get commit :sha) (magit-glab-mr-head-sha mr))
                        (not (magit-glab-landing-problem mr)))
             do (setq top mr))
    top))

(defun magit-glab--status-changed (key)
  "Refresh this status buffer when the dashboard was fetched, if shown."
  (when (and (eq key 'dashboard)
             (derived-mode-p 'magit-status-mode)
             (get-buffer-window nil 'visible))
    (magit-glab-refresh-soon)))

;;;; The transient

(defun magit-glab--dispatch-description ()
  "Return the heading of `magit-glab-dispatch'."
  (let ((key (ignore-errors (magit-glab-current-key t))))
    (if-let* ((mr (and key (magit-glab-get-mr key))))
        (format "GitLab !%d %s" (cdr key) (magit-glab-mr-title mr))
      "GitLab")))

(defun magit-glab--push-stack ()
  "Run `magit-push-stack', if it is there."
  (interactive)
  (if (fboundp 'magit-push-stack)
      (call-interactively #'magit-push-stack)
    (user-error "magit-push-stack is not loaded")))

;;;###autoload (autoload 'magit-glab-dispatch "magit-glab" nil t)
(transient-define-prefix magit-glab-dispatch ()
  "GitLab merge request commands."
  [:description magit-glab--dispatch-description
   ["Open"
    ("l" "dashboard" magit-glab-dashboard)
    ("m" "merge request" magit-glab-mr-visit)
    ("o" "in browser" magit-glab-browse)
    ("w" "copy URL" magit-glab-copy-url)
    ("p" "pipeline" magit-glab-pipeline)]
   ["Diff"
    ("d" "newest patchset" magit-glab-mr-diff)
    ("v" "since last seen" magit-glab-diff-since-seen)
    ("V" "patchsets..." magit-glab-diff-patchsets)
    ("W" "worktree" magit-glab-worktree)
    ("X" "prune worktrees" magit-glab-worktree-prune)]
   ["Comment"
    ("c" "on this line" magit-glab-comment-line)
    ("C" "on the merge request" magit-glab-comment)
    ("r" "reply" magit-glab-reply)
    ("R" "resolve/unresolve" magit-glab-toggle-resolved)
    ("D" "done, and resolve" magit-glab-done)
    ("e" "edit note" magit-glab-edit-note)
    ("k" "delete note" magit-glab-delete-note)]
   ["Review"
    ("a" "approve" magit-glab-approve)
    ("A" "unapprove" magit-glab-unapprove)
    ("s" "start review (drafts)" magit-glab-review-start)
    ("P" "publish review" magit-glab-review-publish)
    ("+" "add reviewers" magit-glab-add-reviewers)
    ("-" "remove reviewers" magit-glab-remove-reviewers)
    ("=" "re-request review" magit-glab-rerequest-review)]
   ["Merge request"
    ("M" "land (merge, or label submit)" magit-glab-land)
    ("t" "toggle draft" magit-glab-toggle-draft)
    ("x" "close/reopen" magit-glab-toggle-closed)
    ("g" "push stack" magit-glab--push-stack)
    ("T" "list threads" magit-glab-list-threads)
    ("F" "threads in this file" magit-glab-file-threads-mode)
    ("L" "glab log" magit-glab-show-log)]])

;;;; Setup

(keymap-set magit-glab-thread-section-map "RET" #'magit-glab-visit)

;;;###autoload
(defun magit-glab-setup ()
  "Hook magit-glab into Magit's buffers, and bind @ to `magit-glab-dispatch'.
Undo with `magit-glab-teardown'."
  (interactive)
  (magit-add-section-hook 'magit-status-sections-hook #'magit-glab-insert-stack
                          'magit-insert-unpushed-to-upstream-or-recent 'append)
  (magit-add-section-hook 'magit-revision-sections-hook #'magit-glab-insert-revision-mr
                          'magit-insert-revision-headers 'append)
  (add-hook 'magit-revision-sections-hook #'magit-glab-revision-place-threads 90)
  (magit-add-section-hook 'magit-diff-sections-hook #'magit-glab-insert-diff-header
                          'magit-insert-diff)
  (add-hook 'magit-diff-sections-hook #'magit-glab-diff-place-threads 90)
  (keymap-set magit-mode-map "@" #'magit-glab-dispatch))

(defun magit-glab-teardown ()
  "Undo `magit-glab-setup'."
  (interactive)
  (remove-hook 'magit-status-sections-hook #'magit-glab-insert-stack)
  (remove-hook 'magit-revision-sections-hook #'magit-glab-insert-revision-mr)
  (remove-hook 'magit-revision-sections-hook #'magit-glab-revision-place-threads)
  (remove-hook 'magit-diff-sections-hook #'magit-glab-insert-diff-header)
  (remove-hook 'magit-diff-sections-hook #'magit-glab-diff-place-threads)
  (keymap-unset magit-mode-map "@" t))

(provide 'magit-glab)
;;; magit-glab.el ends here
