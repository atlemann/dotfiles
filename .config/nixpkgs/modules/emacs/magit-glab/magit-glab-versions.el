;;; magit-glab-versions.el --- Patchsets of a merge request, and diffs between them -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; Gerrit's patchset comparison for GitLab merge requests.
;;
;; Each push of an amended commit is a new version of its merge request.
;; GitLab also adds a version whenever the target branch moves, which in
;; a stack is whenever the merge request below is amended, so versions
;; are folded into patchsets: one per head commit, numbered PS1, PS2, ...
;; in the order they were pushed (see `magit-glab--patchsets').  A local
;; commit with the same Change-Id that is not pushed yet is one more,
;; marked "local".
;;
;; `magit-glab-diff-patchsets' diffs two of them.  It is an interdiff,
;; not a tree diff: when the commit was also rebased, a plain diff of the
;; two heads would bring along everything that landed upstream in
;; between.  So when the bases differ, the old patchset is first applied
;; onto the new base -- `git merge-tree', in the object store only, no
;; worktree touched -- and that tree is diffed against the new head.
;; Only if that conflicts does it fall back to `git range-diff'.
;;
;; Old patchsets' commits are fetched by hash when they are not in the
;; repository; gitlab.com keeps them for the merge request.  Patchsets
;; whose patch id equals the previous one's are pure rebases, with nothing
;; to review, and are marked so.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ansi-color)
(require 'magit)
(require 'magit-glab-core)
(require 'magit-glab-threads)

;;;; Patchsets

(defun magit-glab-local-patchset (mr)
  "Return a local commit of MR newer than its pushed patchsets, or nil.
That is the commit of this repository's stack with MR's Change-Id, if it
is not one of MR's heads."
  (when-let* ((change-id (magit-glab-mr-change-id mr))
              ((equal (magit-glab-project) (magit-glab-mr-project mr)))
              (commit (seq-find (lambda (c) (equal (plist-get c :change-id) change-id))
                                (magit-glab-stack-commits)))
              (sha (plist-get commit :sha))
              ((not (seq-find (lambda (p) (equal (magit-glab-patchset-head p) sha))
                              (magit-glab-mr-patchsets mr)))))
    (magit-glab-patchset--create
     :number (1+ (length (magit-glab-mr-patchsets mr)))
     :head sha :base (magit-rev-parse (concat sha "^")) :local t)))

(defun magit-glab-all-patchsets (mr &optional with-local)
  "Return MR's patchsets, oldest first.
With WITH-LOCAL, add the local commit if it is newer."
  (append (magit-glab-mr-patchsets mr)
          (and with-local (when-let* ((local (magit-glab-local-patchset mr)))
                            (list local)))))

(defun magit-glab-rebase-only-p (key previous patchset)
  "Return non-nil if PATCHSET of merge request KEY only rebased PREVIOUS.
That is, if their patch ids are the same.  Nil while unknown; the patch
ids are fetched in the background."
  (when (and previous (not (magit-glab-patchset-local patchset)))
    (let ((a (magit-glab-patch-id key previous))
          (b (magit-glab-patch-id key patchset)))
      (and a b (equal a b)))))

(defun magit-glab-seen-patchset (mr)
  "Return the patchset of MR last diffed or opened to, or nil."
  (when-let* ((head (plist-get (magit-glab-seen (magit-glab-mr-key mr)) :head)))
    (seq-find (lambda (p) (equal (magit-glab-patchset-head p) head))
              (magit-glab-mr-patchsets mr))))

(defun magit-glab-patchset-label (patchset)
  "Return \"PS3\", or \"PS4 (local)\"."
  (format "PS%d%s" (magit-glab-patchset-number patchset)
          (if (magit-glab-patchset-local patchset) " (local)" "")))

(defun magit-glab-insert-patchsets (mr)
  "Insert the patchsets of MR, newest first, as sections."
  (let* ((key (magit-glab-mr-key mr))
         (patchsets (magit-glab-all-patchsets mr t))
         (seen (magit-glab-seen-patchset mr))
         (newest (car (last (magit-glab-mr-patchsets mr)))))
    (magit-insert-section (magit-glab-patchsets nil t)
      (magit-insert-heading
        (format "Patchsets (%d)" (length patchsets)))
      (let (previous rows)
        (dolist (patchset patchsets)
          (push (list patchset previous) rows)
          (setq previous patchset))
        (pcase-dolist (`(,patchset ,previous) rows)
          (magit-insert-section (magit-glab-patchset-section
                                 (magit-glab-patchset-number patchset))
            (magit-insert-heading
              (concat "  "
                      (string-pad (magit-glab-patchset-label patchset) 13)
                      (propertize (substring (magit-glab-patchset-head patchset) 0 10)
                                  'face 'magit-hash)
                      "  "
                      (string-pad (if (magit-glab-patchset-local patchset)
                                      "not pushed"
                                    (magit-glab-age (magit-glab-patchset-created patchset)))
                                  10)
                      (if (magit-glab-rebase-only-p key previous patchset)
                          (propertize "  rebase only" 'face 'shadow)
                        "")
                      (if (eq patchset newest) (propertize "  newest" 'face 'magit-glab-good) "")
                      (if (and seen (eq patchset seen) (not (eq seen newest)))
                          (propertize "  you last saw this" 'face 'magit-glab-new)
                        "")))))))))

;;;; Reading patchsets

(defun magit-glab--read-patchset (mr prompt default &optional allow-base)
  "Read one of MR's patchsets with PROMPT, DEFAULT being one of them.
With ALLOW-BASE, \"base\" -- the target branch -- is a choice too, and
is returned as `base'."
  (let* ((patchsets (magit-glab-all-patchsets mr t))
         (choices (append (and allow-base '(("base" . base)))
                          (mapcar (lambda (p)
                                    (cons (format "%s %s %s" (magit-glab-patchset-label p)
                                                  (substring (magit-glab-patchset-head p) 0 8)
                                                  (if (magit-glab-patchset-local p) ""
                                                    (magit-glab-age
                                                     (magit-glab-patchset-created p))))
                                          p))
                                  (reverse patchsets))))
         (default (car (rassq default choices)))
         (answer (completing-read (format "%s (default %s): " prompt default)
                                  choices nil t nil nil default)))
    (cdr (assoc answer choices))))

(defun magit-glab--default-patchsets (mr)
  "Return (FROM . TO): what to diff by default on MR.
TO is the local commit if there is one, else the newest patchset.  FROM
is the patchset last seen if it is older than TO, else the one before
TO."
  (let* ((all (magit-glab-all-patchsets mr t))
         (to (car (last all)))
         (seen (magit-glab-seen-patchset mr))
         (from (if (and seen (< (magit-glab-patchset-number seen)
                                (magit-glab-patchset-number to)))
                   seen
                 (car (last all 2)))))
    (cons (if (eq from to) 'base from) to)))

;;;; Diffing

;;;###autoload
(defun magit-glab-diff-patchsets (key from to)
  "Diff patchset FROM of merge request KEY against patchset TO.
FROM may be `base', for the merge request's diff as of TO.  When both
are patchsets and the commit was rebased in between, upstream changes
are left out.  Interactively, ask, defaulting to what changed since the
patchset last seen, or else since the one before the newest."
  (interactive
   (let* ((key (magit-glab-current-key))
          (mr (magit-glab-full-mr key))
          (default (magit-glab--default-patchsets mr)))
     (if (and (not current-prefix-arg) (eq this-command 'magit-glab-diff-since-seen))
         (list key (car default) (cdr default))
       (let* ((to (magit-glab--read-patchset mr "Diff to" (cdr default)))
              (from (magit-glab--read-patchset mr "Diff from"
                                               (if (eq (car default) to) 'base (car default))
                                               t)))
         (list key from to)))))
  (let* ((mr (magit-glab-full-mr key))
         (default-directory (magit-glab-mr-directory key))
         (newest (car (last (magit-glab-mr-patchsets mr)))))
    (magit-glab-ensure-commits
     key (append (list (magit-glab-patchset-head to) (magit-glab-patchset-base to))
                 (and (magit-glab-patchset-p from)
                      (list (magit-glab-patchset-head from) (magit-glab-patchset-base from)))))
    (unless (magit-glab-patchset-local to)
      (magit-glab-mark-seen key :head (magit-glab-patchset-head to)))
    (cond
     ((eq from 'base)
      (magit-glab-show-diff
       default-directory
       (format "%s..%s" (magit-glab-patchset-base to) (magit-glab-patchset-head to))
       (list :key key :new-head (magit-glab-patchset-head to)
             :commentable (eq to newest)
             :label (format "%s" (magit-glab-patchset-label to)))))
     ((equal (magit-glab-patchset-base from) (magit-glab-patchset-base to))
      (magit-glab-show-diff
       default-directory
       (format "%s..%s" (magit-glab-patchset-head from) (magit-glab-patchset-head to))
       (list :key key :new-head (magit-glab-patchset-head to)
             :old-head (magit-glab-patchset-head from)
             :label (format "%s -> %s" (magit-glab-patchset-label from)
                            (magit-glab-patchset-label to)))))
     (t
      (let ((tree (magit-glab--rebased-tree from to)))
        (if tree
            (magit-glab-show-diff
             default-directory
             (format "%s..%s" tree (magit-glab-patchset-head to))
             (list :key key :new-head (magit-glab-patchset-head to)
                   :old-head (magit-glab-patchset-head from)
                   :label (format "%s -> %s (rebased in between; upstream changes left out)"
                                  (magit-glab-patchset-label from)
                                  (magit-glab-patchset-label to))))
          (magit-glab--range-diff key from to)))))))

;;;###autoload
(defun magit-glab-diff-since-seen (key)
  "Diff merge request KEY from the patchset last seen to the newest.
Or, if the newest was seen, from the one before it.  With a prefix
argument, ask which patchsets, as `magit-glab-diff-patchsets' does."
  (interactive (list (magit-glab-current-key)))
  (if current-prefix-arg
      (call-interactively #'magit-glab-diff-patchsets)
    (let* ((mr (magit-glab-full-mr key))
           (default (magit-glab--default-patchsets mr)))
      (magit-glab-diff-patchsets key (car default) (cdr default)))))

(defun magit-glab--rebased-tree (from to)
  "Return a commit of patchset FROM applied onto TO's base, or nil.
Nil if that conflicts.  Magit diffs commits, not trees, so the tree
`git merge-tree' makes is wrapped in a commit whose parent is TO's base.
Nothing but the object store is touched: no ref, index or worktree."
  (with-temp-buffer
    (let ((exit (magit-process-git t "merge-tree" "--write-tree"
                                   (concat "--merge-base=" (magit-glab-patchset-base from))
                                   (magit-glab-patchset-base to)
                                   (magit-glab-patchset-head from))))
      (goto-char (point-min))
      (when (and (eq exit 0) (looking-at "[0-9a-f]\\{40,\\}"))
        (magit-git-string "commit-tree" (match-string 0)
                          "-p" (magit-glab-patchset-base to)
                          "-m" (format "%s rebased onto the base of %s"
                                       (magit-glab-patchset-label from)
                                       (magit-glab-patchset-label to)))))))

(defun magit-glab--range-diff (key from to)
  "Show `git range-diff' of patchsets FROM and TO of merge request KEY."
  (let* ((directory default-directory)
         (buffer (get-buffer-create (format "*magit-glab-range-diff !%d*" (cdr key)))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq default-directory directory)
        (insert (format "%s -> %s of !%d: rebasing %s onto the new base conflicts, so this\n"
                        (magit-glab-patchset-label from) (magit-glab-patchset-label to)
                        (cdr key) (magit-glab-patchset-label from))
                "is git range-diff: a diff of the two patches.  Lines starting with -/+ in\n"
                "the first column are what changed between them.\n\n")
        (let ((start (point)))
          (magit-process-git t "range-diff" "--color=always"
                             (format "%s..%s" (magit-glab-patchset-base from)
                                     (magit-glab-patchset-head from))
                             (format "%s..%s" (magit-glab-patchset-base to)
                                     (magit-glab-patchset-head to)))
          (ansi-color-apply-on-region start (point-max)))
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buffer)))

(provide 'magit-glab-versions)
;;; magit-glab-versions.el ends here
