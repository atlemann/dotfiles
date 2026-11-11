;;; magit-glab-dashboard.el --- What needs you on GitLab -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (magit "4.0"))
;; Keywords: vc, tools

;;; Commentary:
;; `magit-glab-dashboard' is a personal inbox across projects:
;;
;;   To-do          GitLab's to-dos: mentions, review requests, failed
;;                  pipelines.  Visiting the merge request marks them done.
;;   My merge requests, as stacks -- each merge request under the one
;;                  whose branch it targets, as push-stack makes them.
;;   To review      where you are a reviewer and have not approved.
;;   Assigned to me other people's merge requests assigned to you.
;;   Approved by me, waiting on others (collapsed).
;;
;; Each line: number, approvals, pipeline, open threads, title, notes new
;; since you last opened it, merge problems, author and age.  It opens at
;; once from the cache and refreshes in the background.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-glab-core)
(require 'magit-glab-mr)

(declare-function magit-glab-land "magit-glab")
(declare-function magit-glab-dispatch "magit-glab")
(declare-function magit-glab-approve "magit-glab")
(declare-function magit-glab-browse "magit-glab")
(declare-function magit-glab-copy-url "magit-glab")
(declare-function magit-glab-todo-done "magit-glab")

(defvar-keymap magit-glab-dashboard-mode-map
  :doc "Keys in the GitLab dashboard."
  "g"   #'magit-glab-dashboard-refresh
  "q"   #'quit-window
  "RET" #'magit-glab-visit
  "o"   #'magit-glab-browse
  "w"   #'magit-glab-copy-url
  "W"   #'magit-glab-worktree
  "d"   #'magit-glab-mr-diff
  "v"   #'magit-glab-diff-since-seen
  "a"   #'magit-glab-approve
  "M"   #'magit-glab-land
  "x"   #'magit-glab-todo-done
  "@"   #'magit-glab-dispatch)

(define-derived-mode magit-glab-dashboard-mode magit-section-mode "GitLab"
  "The user's GitLab merge requests and to-dos.

\\{magit-glab-dashboard-mode-map}"
  :interactive nil
  (setq-local revert-buffer-function (lambda (&rest _) (magit-glab-dashboard-refresh))))

;;;###autoload
(defun magit-glab-dashboard ()
  "Show your merge requests, the ones to review, and your to-dos."
  (interactive)
  (let ((buffer (get-buffer-create "*magit-glab-dashboard*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'magit-glab-dashboard-mode)
        (magit-glab-dashboard-mode)
        (setq default-directory (expand-file-name "~/"))
        (magit-glab-subscribe #'magit-glab--dashboard-changed)))
    (pop-to-buffer-same-window buffer)
    (magit-glab--dashboard-render)
    (magit-glab-ensure-dashboard 10)))

(defun magit-glab-dashboard-refresh ()
  "Fetch the dashboard again."
  (interactive nil magit-glab-dashboard-mode)
  (magit-glab-refresh-dashboard)
  (magit-glab--dashboard-render))

(defun magit-glab--dashboard-changed (key)
  "Render the dashboard again when its data, or a merge request, changed."
  (when (or (eq key 'dashboard) (consp key))
    (magit-glab-refresh-soon nil #'magit-glab--dashboard-render)))

(defun magit-glab--dashboard-heading (title count &optional face)
  "Insert the heading of a dashboard section: TITLE and COUNT."
  (magit-insert-heading
    (concat (propertize title 'face (or face 'magit-section-heading))
            (propertize (format " (%d)" count) 'face 'shadow))))

(defun magit-glab--insert-tree (tree depth projects)
  "Insert the stack TREE, DEPTH levels in.
PROJECTS non-nil means merge requests from several projects are shown."
  (let ((mr (car tree)))
    (magit-insert-section (magit-glab-mr-section (magit-glab-mr-key mr))
      (magit-insert-heading
        (concat (make-string (* 2 (1+ depth)) ?\s)
                (magit-glab-format-mr mr)
                (if projects
                    (propertize (concat "  " (magit-glab-mr-project mr)) 'face 'shadow)
                  ""))))
    (dolist (child (cdr tree))
      (magit-glab--insert-tree child (1+ depth) projects))))

(defun magit-glab--insert-mrs (mrs projects)
  "Insert MRS one per line, by someone else; PROJECTS as for trees."
  (dolist (mr mrs)
    (magit-insert-section (magit-glab-mr-section (magit-glab-mr-key mr))
      (magit-insert-heading
        (concat "  " (magit-glab-format-mr mr t)
                (if projects
                    (propertize (concat "  " (magit-glab-mr-project mr)) 'face 'shadow)
                  ""))))))

(defun magit-glab--todo-string (todo)
  "Return the line of a to-do plist TODO."
  (format "  %s  %s %s: %s"
          (propertize (format "!%s" (plist-get todo :iid)) 'face 'magit-hash)
          (propertize (string-replace "_" " " (or (plist-get todo :action) ""))
                      'face 'magit-glab-new)
          (magit-glab-author-string (or (plist-get todo :author) "?"))
          (magit-glab-first-line (or (plist-get todo :title) "") 70)))

(defun magit-glab--dashboard-render ()
  "Fill the dashboard from the cache."
  (let* ((data magit-glab--dashboard)
         (me (and data (magit-glab-username)))
         (authored (magit-glab-dashboard-mrs :authored))
         (review (magit-glab-dashboard-mrs :review))
         (assigned (seq-remove (lambda (mr) (equal (magit-glab-mr-author mr) me))
                               (magit-glab-dashboard-mrs :assigned)))
         (approved (seq-filter (lambda (mr) (member me (magit-glab-mr-approved-by mr))) review))
         (to-review (seq-remove (lambda (mr) (member me (magit-glab-mr-approved-by mr))) review))
         (todos (plist-get data :todos))
         (projects (cdr (delete-dups (mapcar #'magit-glab-mr-project
                                             (append authored review assigned))))))
    (magit-glab-with-rerender
      (magit-insert-section (magit-glab-dashboard-root)
        (magit-insert-heading
          (concat (propertize "GitLab" 'face 'magit-section-heading)
                  (if me (concat "  " (magit-glab-author-string me)) "")
                  (propertize
                   (cond ((magit-glab-fetching-p 'dashboard) "  fetching...")
                         ((plist-get data :time)
                          (format "  updated %s ago"
                                  (let ((seconds (- (float-time) (plist-get data :time))))
                                    (if (< seconds 60) (format "%ds" seconds)
                                      (format "%dm" (/ seconds 60))))))
                         (""))
                   'face 'shadow)))
        (insert "\n")
        (if (not data)
            (insert (if (magit-glab-fetching-p 'dashboard) "Fetching...\n"
                      "Nothing fetched yet; g to fetch.\n"))
          (when todos
            (magit-insert-section (magit-glab-todos)
              (magit-glab--dashboard-heading "To-do" (length todos) 'magit-glab-new)
              (dolist (todo todos)
                (magit-insert-section (magit-glab-todo-section
                                       (cons (plist-get todo :project) (plist-get todo :iid)))
                  (magit-insert-heading
                    (propertize (magit-glab--todo-string todo) 'magit-glab-todo
                                (plist-get todo :id)))))
              (insert "\n")))
          (magit-insert-section (magit-glab-authored)
            (magit-glab--dashboard-heading "My merge requests" (length authored))
            (dolist (tree (magit-glab-mr-trees authored))
              (magit-glab--insert-tree tree 0 projects))
            (insert "\n"))
          (magit-insert-section (magit-glab-to-review)
            (magit-glab--dashboard-heading "To review" (length to-review))
            (magit-glab--insert-mrs to-review projects)
            (insert "\n"))
          (when assigned
            (magit-insert-section (magit-glab-assigned)
              (magit-glab--dashboard-heading "Assigned to me" (length assigned))
              (magit-glab--insert-mrs assigned projects)
              (insert "\n")))
          (when approved
            (magit-insert-section (magit-glab-approved nil t)
              (magit-glab--dashboard-heading "Approved by me, waiting on others"
                                             (length approved))
              (magit-glab--insert-mrs approved projects)
              (insert "\n"))))))))

(provide 'magit-glab-dashboard)
;;; magit-glab-dashboard.el ends here
