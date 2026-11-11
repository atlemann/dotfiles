;;; magit-glab-threads.el --- Review threads inside diffs and files -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; Inline review comments where they belong: under the line they were
;; made on.
;;
;; In Magit diff buffers.  `magit-glab-mr-diff' shows a merge request's
;; diff, base..head, in an ordinary `magit-diff-mode' buffer -- every diff
;; command still works -- and places each thread under its line.  Placing
;; is done by overlays, not by inserting text, so staging, visiting and
;; refreshing are untouched; the threads come back after each refresh.
;;
;; In `magit-revision-mode' buffers.  `magit-show-commit' of a commit
;; with a merge request gets a line about the merge request at the top
;; and its threads in the diff.  For a push-stack merge request the
;; commit's diff is the merge request's.
;;
;; A position (GitLab's `position' of a DiffNote) names a line on the new
;; side (new_line, for added and context lines) or the old side (old_line
;; only, for removed lines).  A thread made on an earlier patchset is
;; placed by the same numbers and labelled with its patchset, as its line
;; may have moved since.
;;
;; In file buffers.  `magit-glab-file-threads-mode' marks the lines of the
;; working tree that open threads of the stack's merge requests are on,
;; following the line through what changed since: one `git diff -U0' per
;; file.  `magit-glab-list-threads' lists them all in a grep buffer, so
;; `next-error' walks a review.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-core)

(defcustom magit-glab-place-outdated-threads t
  "Whether threads made on an earlier patchset are placed in diffs too.
They are placed by their line numbers, which may have moved since,
and are marked with their patchset."
  :group 'magit-glab
  :type 'boolean)

;;;; Diff context

(defvar-local magit-glab-diff-context nil
  "What this diff buffer shows of a merge request, a plist:
:key, :range (the `magit-buffer-diff-range' it applies to), :new-head
and :old-head (the patchset heads whose threads go on the new and old
side), :commentable (the diff is the merge request's own, so new
comments can be positioned on it), and :label.")
(put 'magit-glab-diff-context 'permanent-local t)

(defun magit-glab--diff-context ()
  "Return this buffer's diff context, if it still applies.
Magit reuses one diff buffer for every diff, so a context set for one
range must not stick to the next."
  (and magit-glab-diff-context
       (equal (plist-get magit-glab-diff-context :range) magit-buffer-diff-range)
       magit-glab-diff-context))

(defun magit-glab-show-diff (directory range context)
  "Show RANGE in DIRECTORY's repository as the merge request diff CONTEXT.
CONTEXT is a `magit-glab-diff-context' plist without :range."
  (let ((default-directory directory)
        (context (plist-put (copy-sequence context) :range range)))
    (magit-setup-buffer #'magit-diff-mode nil
      (magit-buffer-diff-range range)
      (magit-buffer-diff-typearg nil)
      (magit-buffer-diff-type 'committed)
      (magit-buffer-diff-args (car (magit-diff-arguments 'magit-diff-mode)))
      (magit-buffer-diff-files nil)
      (magit-buffer-diff-files-suspended nil)
      (magit-glab-diff-context context)
      (magit-glab-buffer-key (plist-get context :key)))))

(defun magit-glab-insert-diff-header ()
  "Insert what merge request diff this is, in a diff buffer showing one."
  (when-let* ((context (magit-glab--diff-context))
              (mr (magit-glab-get-mr (plist-get context :key)))
              (start (point)))
    (magit-insert-section (magit-glab-mr-section (plist-get context :key))
      (magit-insert-heading
        (concat (propertize (format "!%d" (magit-glab-mr-iid mr)) 'face 'magit-hash)
                " " (magit-glab-mr-title mr)
                (if-let* ((label (plist-get context :label)))
                    (concat "\n" (propertize label 'face 'magit-section-heading))
                  "")))
      (insert "\n"))
    (magit-glab-adopt-faces start (point))))

;;;; Commits

(defun magit-glab-ensure-commits (key shas)
  "Make sure the commits SHAS of merge request KEY are in this repository.
Fetch the merge request's head ref, and then by hash whatever is still
missing -- gitlab.com serves old versions of a merge request by hash.
Each fetched commit is kept by a ref under refs/glab/, so `git gc' does
not take it again."
  (let ((missing (seq-remove (lambda (sha) (magit-commit-p sha)) (delete-dups (delq nil shas)))))
    (when missing
      (magit-call-git "fetch" "--quiet" "--no-write-fetch-head" magit-glab-remote
                      (format "+refs/merge-requests/%d/head:refs/glab/mr/%d/head"
                              (cdr key) (cdr key)))
      (setq missing (seq-remove #'magit-commit-p missing)))
    (when missing
      (magit-call-git "fetch" "--quiet" "--no-write-fetch-head" magit-glab-remote
                      (mapcar (lambda (sha)
                                (format "%s:refs/glab/mr/%d/%s" sha (cdr key) sha))
                              missing))
      (when-let* ((still (seq-remove #'magit-commit-p missing)))
        (user-error "Cannot fetch %s from %s"
                    (mapconcat (lambda (sha) (substring sha 0 8)) still ", ")
                    magit-glab-remote)))))

(defun magit-glab-mr-directory (key)
  "Return the repository merge request KEY is checked out in, asking if needed."
  (magit-glab-project-directory (car key) t))

;;;###autoload
(defun magit-glab-mr-diff (key)
  "Show the diff of merge request KEY, base..head, with its threads."
  (interactive (list (magit-glab-current-key)))
  (let* ((mr (magit-glab-full-mr key))
         (refs (or (magit-glab-mr-diff-refs mr)
                   (user-error "GitLab has no diff for !%d" (cdr key))))
         (default-directory (magit-glab-mr-directory key)))
    (magit-glab-ensure-commits key (list (plist-get refs :base) (plist-get refs :head)))
    (magit-glab-show-diff
     default-directory
     (format "%s..%s" (plist-get refs :base) (plist-get refs :head))
     (list :key key :new-head (plist-get refs :head) :commentable t
           :label (format "Diff of the newest patchset, PS%d"
                          (length (magit-glab-mr-patchsets mr)))))))

(defun magit-glab-full-mr (key)
  "Return merge request KEY with its discussions, fetching it if need be.
Waits for GitLab; for interactive commands."
  (let ((mr (magit-glab-get-mr key)))
    (if (and mr (magit-glab-mr-full-p mr))
        mr
      (magit-glab--wait-for-mr key))))

(defun magit-glab--wait-for-mr (key)
  "Fetch merge request KEY and wait for it; return it."
  (let (done)
    (magit-glab-refresh-mr key (lambda (ok) (setq done (list ok))))
    (with-timeout (magit-glab-sync-timeout
                   (user-error "magit-glab: no answer from GitLab for !%d" (cdr key)))
      (while (not done) (accept-process-output nil 0.05)))
    (or (magit-glab-get-mr key)
        (user-error "magit-glab: could not fetch !%d" (cdr key)))))

;;;; Lines of a diff

(defun magit-glab-hunk-lines (hunk)
  "Return the lines of HUNK as (POSITION OLD-LINE NEW-LINE), in order.
OLD-LINE is nil for an added line, NEW-LINE for a removed one."
  (unless (oref hunk combined)
    (let ((old (car (oref hunk from-range)))
          (new (car (oref hunk to-range)))
          lines)
      (save-excursion
        (goto-char (oref hunk content))
        (while (< (point) (oref hunk end))
          (pcase (char-after)
            (?+ (push (list (point) nil new) lines) (cl-incf new))
            (?- (push (list (point) old nil) lines) (cl-incf old))
            (?\s (push (list (point) old new) lines) (cl-incf old) (cl-incf new)))
          (forward-line)))
      (nreverse lines))))

(defun magit-glab--file-sections ()
  "Return the file sections of this diff buffer."
  (let (files)
    (when magit-root-section
      (magit-map-sections (lambda (section)
                            (when (magit-file-section-p section)
                              (push section files)))))
    (nreverse files)))

(defun magit-glab--file-section-paths (file)
  "Return (OLD-PATH . NEW-PATH) of the diff FILE section."
  (cons (or (oref file source) (oref file value)) (oref file value)))

(defun magit-glab--hunk-at-point ()
  "Return the hunk section point is in, or nil."
  (let ((section (magit-current-section)))
    (and (magit-hunk-section-p section) section)))

(defun magit-glab-diff-line-at-point ()
  "Return the diff line at point as a plist, or nil.
The plist has :old-path, :new-path, :old-line and :new-line (nil on
the side the line is not on), and :text, the line without its prefix."
  (when-let* ((hunk (magit-glab--hunk-at-point))
              (file (oref hunk parent))
              (bol (line-beginning-position))
              (line (assq bol (magit-glab-hunk-lines hunk))))
    (pcase-let ((`(,old-path . ,new-path) (magit-glab--file-section-paths file)))
      (list :old-path old-path :new-path new-path
            :old-line (nth 1 line) :new-line (nth 2 line)
            :text (buffer-substring-no-properties (1+ bol) (line-end-position))))))

(defun magit-glab-hunk-region-lines ()
  "Return the diff lines of the active region, if within one hunk.
A list of plists as `magit-glab-diff-line-at-point' returns."
  (when-let* (((use-region-p))
              (hunk (magit-glab--hunk-at-point))
              (file (oref hunk parent)))
    (let ((start (save-excursion (goto-char (region-beginning)) (line-beginning-position)))
          (end (save-excursion (goto-char (region-end))
                               (if (bolp) (1- (point)) (point)))))
      (pcase-let ((`(,old-path . ,new-path) (magit-glab--file-section-paths file)))
        (delq nil
              (mapcar (pcase-lambda (`(,pos ,old ,new))
                        (when (and (>= pos start) (<= pos end))
                          (list :old-path old-path :new-path new-path
                                :old-line old :new-line new
                                :text (buffer-substring-no-properties
                                       (1+ pos) (save-excursion (goto-char pos)
                                                                (line-end-position))))))
                      (magit-glab-hunk-lines hunk)))))))

;;;; Placing threads

(defun magit-glab--remove-thread-overlays ()
  "Remove the thread overlays of this buffer."
  (remove-overlays (point-min) (point-max) 'magit-glab-threads t))

(defun magit-glab--find-line (files path side line)
  "Return the buffer position of LINE of PATH on SIDE of the diff FILES.
SIDE is `new' or `old'."
  (catch 'found
    (dolist (file files)
      (pcase-let ((`(,old-path . ,new-path) (magit-glab--file-section-paths file)))
        (when (equal path (if (eq side 'new) new-path old-path))
          (dolist (hunk (oref file children))
            (when (magit-hunk-section-p hunk)
              (dolist (entry (magit-glab-hunk-lines hunk))
                (when (and (equal (if (eq side 'new) (nth 2 entry) (nth 1 entry)) line)
                           ;; A removed line is only matched on the old side.
                           (or (eq side 'old) (nth 2 entry)))
                  (throw 'found (car entry)))))))))))

(defun magit-glab-thread-specs (mr new-head old-head)
  "Return where MR's inline threads go in a diff.
Each is (DISCUSSION SIDE LINE PATH LABEL).  Threads made on NEW-HEAD
go on the new side by their position; when OLD-HEAD is given, threads
made on it go on the old side.  Threads on other patchsets go on the
new side with a label, if `magit-glab-place-outdated-threads'."
  (let ((patchsets (magit-glab-mr-patchsets mr))
        specs)
    (dolist (discussion (magit-glab-visible-discussions mr))
      (when-let* ((position (magit-glab-discussion-position discussion)))
        (let* ((head (plist-get position :head))
               (new-line (plist-get position :new-line))
               (old-line (plist-get position :old-line))
               (patchset (seq-find (lambda (p) (equal (magit-glab-patchset-head p) head))
                                   patchsets))
               (label (and patchset (format "on PS%d" (magit-glab-patchset-number patchset)))))
          (cond
           ((equal head new-head)
            (push (if new-line
                      (list discussion 'new new-line (plist-get position :new-path) nil)
                    (list discussion 'old old-line (plist-get position :old-path) nil))
                  specs))
           ((and old-head (equal head old-head))
            ;; The old side of a diff between patchsets is the old patchset.
            (when new-line
              (push (list discussion 'old new-line (plist-get position :new-path) label)
                    specs)))
           ((and magit-glab-place-outdated-threads (not old-head))
            (push (if new-line
                      (list discussion 'new new-line (plist-get position :new-path)
                            (or label "on an earlier version"))
                    (list discussion 'old old-line (plist-get position :old-path)
                          (or label "on an earlier version")))
                  specs))))))
    (nreverse specs)))

(defun magit-glab-place-threads (key specs)
  "Show the threads SPECS of merge request KEY under their diff lines.
SPECS are as `magit-glab-thread-specs' returns.  Return how many were
placed."
  (magit-glab--remove-thread-overlays)
  (let ((files (magit-glab--file-sections))
        (by-line (make-hash-table))
        (placed 0))
    (pcase-dolist (`(,discussion ,side ,line ,path ,label) specs)
      (when-let* ((pos (and line (magit-glab--find-line files path side line))))
        (push (cons discussion label) (gethash pos by-line))
        (cl-incf placed)))
    (maphash
     (lambda (pos entries)
       (let ((overlay (save-excursion
                        (goto-char pos)
                        (make-overlay (line-beginning-position) (line-end-position)
                                      nil t nil)))
             (entries (nreverse entries)))
         (overlay-put overlay 'magit-glab-threads t)
         (overlay-put overlay 'magit-glab-key key)
         (overlay-put overlay 'magit-glab-discussions (mapcar #'car entries))
         (overlay-put overlay 'after-string
                      (concat "\n"
                              (string-trim-right
                               (mapconcat
                                (pcase-lambda (`(,discussion . ,label))
                                  (concat (if label
                                              (propertize (format "  ┃ (%s)\n" label)
                                                          'face '(magit-glab-thread shadow))
                                            "")
                                          (magit-glab-discussion-string discussion)))
                                entries ""))))))
     by-line)
    placed))

(defun magit-glab--place-in-diff-buffer ()
  "Place the threads of this diff buffer's merge request, if it has one."
  (if-let* ((context (magit-glab--diff-context))
            (key (plist-get context :key))
            (mr (magit-glab-get-mr key)))
      (magit-glab-place-threads
       key (magit-glab-thread-specs mr (plist-get context :new-head)
                                    (plist-get context :old-head)))
    (magit-glab--remove-thread-overlays)))

(defun magit-glab-diff-place-threads ()
  "Show merge request threads in this diff buffer; for `magit-diff-sections-hook'."
  (when (magit-glab--diff-context)
    (magit-glab-subscribe #'magit-glab--diff-changed)
    (magit-glab--place-in-diff-buffer)))

(defun magit-glab--diff-changed (key)
  "Re-place this diff buffer's threads if merge request KEY changed."
  (when (and (magit-glab--diff-context)
             (equal key (plist-get (magit-glab--diff-context) :key)))
    (magit-glab--place-in-diff-buffer)))

;;;; Revision buffers

(defvar-local magit-glab--revision-key nil
  "The key of the merge request of this revision buffer's commit, or `none'.")

(defun magit-glab--revision-key ()
  "Return the key of the merge request of this revision buffer's commit.
Look the commit's Change-Id up in the cache, and when it is not there,
ask GitLab in the background; the buffer is refreshed when it answers."
  (let ((rev magit-buffer-revision-oid))
    (unless (and (consp magit-glab--revision-key)
                 (equal (car magit-glab--revision-key) rev)
                 (cdr magit-glab--revision-key))
      (let* ((project (magit-glab-project))
             (change-id (and project (magit-glab-change-id rev)))
             (mr (and change-id (magit-glab-mr-for-change-id project change-id))))
        (when (and change-id (not mr))
          (magit-glab-subscribe #'magit-glab--revision-changed)
          (magit-glab-lookup-change-id project change-id))
        (setq magit-glab--revision-key (cons rev (and mr (magit-glab-mr-key mr))))))
    (cdr magit-glab--revision-key)))

(defun magit-glab-insert-revision-mr ()
  "Insert a line about the merge request of this commit, if it has one.
For `magit-revision-sections-hook'."
  (when-let* ((key (magit-glab--revision-key))
              (mr (magit-glab-ensure-mr key)))
    (setq magit-glab-buffer-key key)
    (magit-glab-subscribe #'magit-glab--revision-changed)
    (let* ((rev magit-buffer-revision-oid)
           (patchset (seq-find (lambda (p) (equal (magit-glab-patchset-head p) rev))
                               (magit-glab-mr-patchsets mr)))
           (newest (car (last (magit-glab-mr-patchsets mr))))
           (start (point)))
      (magit-insert-section (magit-glab-mr-section key)
        (magit-insert-heading
          (concat (propertize "Merge request " 'face 'magit-section-heading)
                  (magit-glab-format-mr mr)
                  "\n"
                  (propertize
                   (cond ((not (magit-glab-mr-full-p mr)) "  fetching threads...")
                         ((not patchset)
                          (format "  This commit is not on GitLab yet: newest is PS%d (%s)"
                                  (length (magit-glab-mr-patchsets mr))
                                  (if newest (substring (magit-glab-patchset-head newest) 0 8)
                                    "none")))
                         ((eq patchset newest)
                          (format "  PS%d, the newest" (magit-glab-patchset-number patchset)))
                         ((format "  PS%d of %d" (magit-glab-patchset-number patchset)
                                  (length (magit-glab-mr-patchsets mr)))))
                   'face 'shadow))))
      (magit-glab-adopt-faces start (point)))))

(defun magit-glab-revision-place-threads ()
  "Show this commit's merge request threads in its diff.
For `magit-revision-sections-hook', after the diff is inserted."
  (if-let* ((key (and (consp magit-glab--revision-key) (cdr magit-glab--revision-key)))
            (mr (magit-glab-get-mr key))
            ((magit-glab-mr-full-p mr)))
      (magit-glab-place-threads
       key (magit-glab-thread-specs mr magit-buffer-revision-oid nil))
    (magit-glab--remove-thread-overlays)))

(defun magit-glab--revision-changed (key)
  "Refresh this revision buffer if merge request KEY changed.
Also when the merge request of its commit was not known, and a lookup
of Change-Ids has finished."
  (when (and (derived-mode-p 'magit-revision-mode)
             (or (equal key magit-glab-buffer-key)
                 (and (eq (car-safe key) 'change-id)
                      (consp magit-glab--revision-key)
                      (null (cdr magit-glab--revision-key)))))
    (magit-glab-refresh-soon)))

;;;; The thread at point

(defun magit-glab-discussion-at-point ()
  "Return (KEY . DISCUSSION) for the thread at point, or nil.
That is the thread section point is in, the thread shown under the
diff line point is on (the first, if several), or the thread on this
line of a file buffer or thread list."
  (or
   (let ((section (magit-current-section)))
     (while (and section (not (cl-typep section '(or magit-glab-thread-section
                                                     magit-glab-note-section))))
       (setq section (oref section parent)))
     (when section
       (let ((id (if (magit-glab-note-section-p section)
                     (car (oref section value))
                   (oref section value)))
             (key (magit-glab-current-key t)))
         (when-let* ((mr (and key (magit-glab-get-mr key))))
           (when-let* ((discussion (seq-find (lambda (d) (equal (magit-glab-discussion-id d) id))
                                             (magit-glab-mr-discussions mr))))
             (cons key discussion))))))
   (when-let* ((overlay (seq-find (lambda (o) (overlay-get o 'magit-glab-discussions))
                                  (overlays-in (line-beginning-position)
                                               (line-end-position)))))
     (let* ((key (overlay-get overlay 'magit-glab-key))
            (discussions (overlay-get overlay 'magit-glab-discussions)))
       (cons key
             (if (cdr discussions)
                 (let ((choices (mapcar (lambda (d) (cons (magit-glab-discussion-heading d) d))
                                        discussions)))
                   (cdr (assoc (completing-read "Thread: " choices nil t) choices)))
               (car discussions)))))
   (get-text-property (point) 'magit-glab-thread)))

(defun magit-glab-note-at-point ()
  "Return the note section point is in, as (DISCUSSION-ID . NOTE-ID), or nil."
  (let ((section (magit-current-section)))
    (while (and section (not (magit-glab-note-section-p section)))
      (setq section (oref section parent)))
    (and section (oref section value))))

;;;###autoload
(defun magit-glab-next-thread (&optional backward)
  "Move to the next unresolved thread; with BACKWARD, the previous one.
In a merge request buffer, the next thread section; in a diff or file
buffer, the next line with a thread under it."
  (interactive)
  (let ((start (point)) found)
    (save-excursion
      (while (and (not found)
                  (not (if backward (bobp) (eobp))))
        (forward-line (if backward -1 1))
        (let ((section (magit-current-section)))
          (when (or (and (magit-glab-thread-section-p section)
                         (get-text-property (point) 'magit-glab-open))
                    (seq-some (lambda (o)
                                (seq-some (lambda (d) (not (magit-glab-discussion-resolved d)))
                                          (overlay-get o 'magit-glab-discussions)))
                              (overlays-in (line-beginning-position) (line-end-position))))
            (setq found (point))))))
    (if found
        (goto-char found)
      (goto-char start)
      (message "No %s unresolved thread" (if backward "previous" "next")))))

;;;###autoload
(defun magit-glab-previous-thread ()
  "Move to the previous unresolved thread."
  (interactive)
  (magit-glab-next-thread t))

;;;; Following lines into the working tree

(defun magit-glab-parse-hunk-headers (diff)
  "Return the hunks of the unified DIFF text.
Each is (OLD-START OLD-LEN NEW-START NEW-LEN)."
  (let (hunks (start 0))
    (while (string-match "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
                         diff start)
      (push (list (string-to-number (match-string 1 diff))
                  (if (match-string 2 diff) (string-to-number (match-string 2 diff)) 1)
                  (string-to-number (match-string 3 diff))
                  (if (match-string 4 diff) (string-to-number (match-string 4 diff)) 1))
            hunks)
      (setq start (match-end 0)))
    (nreverse hunks)))

(defun magit-glab-map-line (line hunks)
  "Return where LINE of the old side is on the new side of HUNKS.
HUNKS are from `magit-glab-parse-hunk-headers' of a -U0 diff.  Return
(NEW-LINE . EXACT); EXACT is nil when the line itself was changed, and
NEW-LINE is then where the change is."
  (let ((delta 0) result)
    (catch 'done
      (pcase-dolist (`(,old-start ,old-len ,new-start ,new-len) hunks)
        (cond
         ;; Lines inserted after OLD-START.
         ((= old-len 0)
          (if (<= line old-start)
              (throw 'done (setq result (cons (+ line delta) t)))
            (cl-incf delta new-len)))
         ((< line old-start)
          (throw 'done (setq result (cons (+ line delta) t))))
         ((< line (+ old-start old-len))
          (throw 'done (setq result (cons (max new-start 1) nil))))
         (t (cl-incf delta (- new-len old-len)))))
      (setq result (cons (+ line delta) t)))
    result))

(defun magit-glab--stack-threads (&optional all)
  "Return the open threads of this stack's merge requests.
A list of (KEY DISCUSSION HEAD PATH LINE).  With ALL, resolved ones
too.  Merge requests not fetched yet are fetched in the background."
  (let ((project (magit-glab-project))
        threads)
    (dolist (commit (magit-glab-stack-commits))
      (when-let* ((mr (magit-glab-mr-for-change-id project (plist-get commit :change-id)))
                  (key (magit-glab-mr-key mr))
                  (mr (magit-glab-ensure-mr key)))
        (dolist (discussion (magit-glab-visible-discussions mr))
          (when-let* ((position (magit-glab-discussion-position discussion))
                      (line (plist-get position :new-line)))
            (when (or all (not (magit-glab-discussion-resolved discussion)))
              (push (list key discussion (plist-get position :head)
                          (plist-get position :new-path) line)
                    threads))))))
    (nreverse threads)))

(defun magit-glab--working-tree-line (head path line cache)
  "Return (LINE . EXACT): where LINE of PATH at commit HEAD is in the working tree.
CACHE is a hash table keeping the diff of each HEAD and PATH, so a file
costs one git call per head however many threads it has."
  (let ((hunks (with-memoization (gethash (cons head path) cache)
                 (if (magit-commit-p head)
                     (magit-glab-parse-hunk-headers
                      (magit-git-output "diff" "--no-ext-diff" "--no-color" "-U0"
                                        head "--" path))
                   'missing))))
    (if (eq hunks 'missing)
        (cons line nil)
      (magit-glab-map-line line hunks))))

;;;###autoload
(defun magit-glab-list-threads (&optional all)
  "List the open threads of this stack's merge requests, in a grep buffer.
Each at its line in the working tree, so `next-error' visits them.
With a prefix argument ALL, resolved threads too."
  (interactive "P")
  (let* ((top (or (magit-toplevel) (user-error "Not inside a Git repository")))
         (default-directory top)
         (threads (magit-glab--stack-threads all))
         (buffer (get-buffer-create "*magit-glab-threads*"))
         (cache (make-hash-table :test #'equal)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq default-directory top)
        (insert (format "Threads of the stack in %s%s\n\n" top
                        (if (seq-some (lambda (k) (magit-glab-fetching-p k))
                                      (delete-dups (mapcar #'car threads)))
                            " (still fetching some; g to refresh)" "")))
        (pcase-dolist (`(,key ,discussion ,head ,path ,line) threads)
          (pcase-let ((`(,new-line . ,exact)
                       (magit-glab--working-tree-line head path line cache)))
            (let ((start (point))
                  (first (magit-glab-discussion-first discussion)))
              (insert (format "%s:%d: !%d %s%s: %s\n" path new-line (cdr key)
                              (if exact "" "(moved) ")
                              (magit-glab-note-author first)
                              (magit-glab-first-line (magit-glab-note-body first) 80)))
              (put-text-property start (point) 'magit-glab-thread (cons key discussion)))))
        (unless threads
          (insert "No open threads.\n"))
        (grep-mode)
        (setq-local revert-buffer-function
                    (lambda (&rest _)
                      (let ((default-directory top))
                        (magit-glab-list-threads all))))))
    (pop-to-buffer buffer)))

;;;; Threads in file buffers

(defvar magit-glab-file-threads-mode)

(defvar-local magit-glab--file-threads nil
  "The threads `magit-glab-file-threads-mode' shows in this buffer.")

(defun magit-glab--file-threads-render ()
  "Show the open threads of this file, at their working-tree lines."
  (magit-glab--remove-thread-overlays)
  (when-let* ((file buffer-file-name)
              (top (magit-toplevel)))
    (let* ((default-directory top)
           (path (file-relative-name file top))
           (threads (seq-filter (lambda (thread) (equal (nth 3 thread) path))
                                (magit-glab--stack-threads)))
           (cache (make-hash-table :test #'equal)))
      (setq magit-glab--file-threads threads)
      (pcase-dolist (`(,key ,discussion ,head ,_ ,line) threads)
        (pcase-let ((`(,new-line . ,exact)
                     (magit-glab--working-tree-line head path line cache)))
          (save-excursion
            (goto-char (point-min))
            (when (zerop (forward-line (1- new-line)))
              (let* ((first (magit-glab-discussion-first discussion))
                     (overlay (make-overlay (line-beginning-position) (line-end-position)
                                            nil t nil)))
                (overlay-put overlay 'magit-glab-threads t)
                (overlay-put overlay 'magit-glab-key key)
                (overlay-put overlay 'magit-glab-discussions (list discussion))
                (overlay-put overlay 'before-string
                             (propertize " " 'display
                                         '(left-fringe right-triangle magit-glab-open)))
                (overlay-put overlay 'after-string
                             (propertize
                              (format "  ◀ !%d %s%s: %s" (cdr key)
                                      (if exact "" "(moved) ")
                                      (magit-glab-note-author first)
                                      (magit-glab-first-line (magit-glab-note-body first) 60))
                              'face 'magit-glab-open)))))))
      (length threads))))

(defun magit-glab--file-threads-changed (key)
  "Re-render this file's threads if merge request KEY is one of them."
  (when (and magit-glab-file-threads-mode
             (or (consp key) (eq key 'dashboard)))
    (magit-glab--file-threads-render)))

;;;###autoload
(define-minor-mode magit-glab-file-threads-mode
  "Show the open review threads of this file's stack at their lines.
Threads are followed from the commit they were made on to the working
tree, and re-placed after each save.  `magit-glab-show-thread' shows the
whole thread on this line; the thread commands (reply, resolve) work
here too."
  :lighter " glab"
  (if magit-glab-file-threads-mode
      (progn
        (magit-glab-subscribe #'magit-glab--file-threads-changed)
        (add-hook 'after-save-hook #'magit-glab--file-threads-render nil t)
        (message "%d open threads in this file" (or (magit-glab--file-threads-render) 0)))
    (remove-hook 'after-save-hook #'magit-glab--file-threads-render t)
    (magit-glab--remove-thread-overlays)))

;;;###autoload
(defun magit-glab-show-thread ()
  "Show the whole thread at point in a side window."
  (interactive)
  (pcase-let ((`(,key . ,discussion) (or (magit-glab-discussion-at-point)
                                         (user-error "No thread here"))))
    (let ((buffer (get-buffer-create "*magit-glab-thread*")))
      (with-current-buffer buffer
        (magit-section-mode)
        (setq magit-glab-buffer-key key)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (magit-insert-section (magit-glab-thread-root)
            (magit-glab-insert-discussion
             discussion (plist-get (magit-glab-seen key) :note)))
          (magit-glab-adopt-faces))
        (goto-char (point-min)))
      (display-buffer buffer '((display-buffer-in-side-window) (side . bottom)
                               (window-height . fit-window-to-buffer))))))

(provide 'magit-glab-threads)
;;; magit-glab-threads.el ends here
