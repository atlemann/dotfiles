;;; magit-glab-worktree.el --- Merge requests checked out in worktrees -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; `magit-glab-worktree' checks a merge request out in a worktree of its
;; own, to build, run and read it with the language server, without
;; touching the main checkout.  The worktree is detached at the merge
;; request's head, fetched into refs/glab/mr/<iid>/head -- a ref of our
;; own, not a branch, so it stays out of the branch lists.  Running it
;; again fetches again and offers to move a clean worktree to a newer
;; head.  Everything runs through Magit, so over TRAMP too.
;;
;; Where the worktree goes is up to
;; `magit-glab-worktree-directory-function', and what happens after --
;; Magit status by default -- to `magit-glab-worktree-open-function'.
;;
;; `magit-glab-worktree-prune' removes the worktrees, and refs, of merge
;; requests that are merged or closed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-core)
(require 'magit-glab-threads)

(defcustom magit-glab-worktree-directory-function
  #'magit-glab-worktree-sibling-directory
  "Function returning where a merge request's worktree goes.
Called with the merge request's key and the top of the main worktree."
  :group 'magit-glab
  :type 'function)

(defcustom magit-glab-worktree-open-function #'magit-status-setup-buffer
  "Function called with the worktree's directory once it is ready."
  :group 'magit-glab
  :type 'function)

(defun magit-glab-worktree-sibling-directory (key main)
  "Return MAIN-mr-IID, next to the main worktree MAIN, for merge request KEY."
  (format "%s-mr-%d/" (directory-file-name main) (cdr key)))

(defun magit-glab--mr-ref (key)
  "Return the ref merge request KEY's head is fetched into."
  (format "refs/glab/mr/%d/head" (cdr key)))

(defun magit-glab--git (&rest args)
  "Run git with ARGS, logged in Magit's process buffer; signal on failure."
  (unless (zerop (apply #'magit-call-git args))
    (user-error "git %s failed; see %s" (car args)
                (substitute-command-keys "\\[magit-process-buffer]"))))

;;;###autoload
(defun magit-glab-worktree (key)
  "Check merge request KEY out in a worktree of its own, and go there."
  (interactive (list (magit-glab-current-key)))
  (let* ((default-directory (magit-glab-mr-directory key))
         (main (magit-glab--main-worktree))
         (directory (file-name-as-directory
                     (funcall magit-glab-worktree-directory-function key main)))
         (ref (magit-glab--mr-ref key))
         ;; Magit lists worktrees as full, and over TRAMP remote, names.
         (existing (seq-find (lambda (worktree)
                               (equal (file-name-as-directory (car worktree)) directory))
                             (magit-list-worktrees))))
    (message "Fetching !%d..." (cdr key))
    (magit-glab--git "fetch" "--quiet" "--no-write-fetch-head" magit-glab-remote
                     (format "+refs/merge-requests/%d/head:%s" (cdr key) ref))
    (let ((head (magit-rev-parse ref)))
      (if existing
          (let ((default-directory directory))
            (cond ((equal (magit-rev-parse "HEAD") head))
                  ((magit-anything-modified-p)
                   (message "!%d has a newer head, but the worktree has changes; left as is"
                            (cdr key)))
                  ((y-or-n-p (format "!%d has a newer head; move the worktree to it? "
                                     (cdr key)))
                   (magit-glab--git "checkout" "--quiet" "--detach" head))))
        (magit-glab--git "worktree" "add" "--detach"
                         (magit-convert-filename-for-git directory) ref)))
    (funcall magit-glab-worktree-open-function directory)))

(defun magit-glab--mr-states (project iids)
  "Return an alist from IIDS of PROJECT to their states, asking GitLab."
  (let ((data (magit-glab-graphql-sync
               "query($project: ID!, $iids: [String!]) {
  project(fullPath: $project) {
    mergeRequests(iids: $iids, first: 100) { nodes { iid state } }
  }
}"
               `((project . ,project)
                 (iids . ,(vconcat (mapcar #'number-to-string iids)))))))
    (mapcar (lambda (node)
              (cons (string-to-number (alist-get 'iid node)) (alist-get 'state node)))
            (magit-glab--nodes (let-alist data .project.mergeRequests)))))

;;;###autoload
(defun magit-glab-worktree-prune ()
  "Remove the worktrees and refs of merge requests that are merged or closed."
  (interactive)
  (let* ((project (or (magit-glab-project) (user-error "Not in a GitLab repository")))
         (worktrees (delq nil (mapcar (lambda (worktree)
                                        (and (string-match "[/-]mr-\\([0-9]+\\)/?\\'"
                                                           (car worktree))
                                             (cons (string-to-number (match-string 1 (car worktree)))
                                                   (car worktree))))
                                      (cdr (magit-list-worktrees)))))
         (refs (magit-git-lines "for-each-ref" "--format=%(refname)" "refs/glab/mr/"))
         (iids (delete-dups
                (append (mapcar #'car worktrees)
                        (delq nil (mapcar (lambda (ref)
                                            (and (string-match "\\`refs/glab/mr/\\([0-9]+\\)/" ref)
                                                 (string-to-number (match-string 1 ref))))
                                          refs)))))
         (done (and iids
                    (mapcar #'car (seq-remove (lambda (state) (equal (cdr state) "opened"))
                                              (magit-glab--mr-states project iids))))))
    (if (null done)
        (message "Nothing to prune")
      (when (y-or-n-p (format "Remove the worktrees and refs of %s? "
                              (mapconcat (lambda (iid) (format "!%d" iid)) done ", ")))
        (dolist (iid done)
          (when-let* ((worktree (alist-get iid worktrees)))
            (unless (zerop (magit-call-git "worktree" "remove"
                                           (magit-convert-filename-for-git worktree)))
              (message "%s has changes; left as is" worktree)))
          (dolist (ref refs)
            (when (string-prefix-p (format "refs/glab/mr/%d/" iid) ref)
              (magit-call-git "update-ref" "-d" ref))))
        (magit-refresh)))))

(provide 'magit-glab-worktree)
;;; magit-glab-worktree.el ends here
