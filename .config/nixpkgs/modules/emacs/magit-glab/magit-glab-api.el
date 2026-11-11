;;; magit-glab-api.el --- Talk to GitLab through the glab CLI -*- lexical-binding: t -*-

;; Author: Tore Aadland
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: vc, tools

;;; Commentary:
;; Every request magit-glab makes goes through `magit-glab-api': it runs
;; `glab api' asynchronously and calls back with the parsed JSON, or with
;; a one-line error.
;;
;; glab always runs on this machine, never over TRAMP: the API does not
;; care where the repository is, and a local process is one less round
;; trip per request.  So `default-directory' is bound to a local directory
;; and the global `exec-path' and `process-environment' are used, not a
;; remote or direnv buffer's.  For the same reason --hostname is always
;; passed: without it, glab guesses the host from the git repository in
;; its working directory.
;;
;; Bodies go to glab as JSON on stdin (--input -).  Comments are
;; multi-line markdown and positions are nested objects, which
;; --raw-field cannot express; and glab installed as a snap cannot read
;; files from /tmp, but can always read stdin.
;;
;; At most `magit-glab-max-processes' glab processes run at once; the rest
;; wait in a queue.  Each request is logged in *magit-glab-log*, with how
;; long it took -- the first place to look when something is slow.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)

(defgroup magit-glab nil
  "GitLab merge requests in Magit, on the glab CLI."
  :group 'tools
  :prefix "magit-glab-")

(defcustom magit-glab-program "glab"
  "The glab executable, looked up on this machine's `exec-path'."
  :type 'string)

(defcustom magit-glab-host "gitlab.com"
  "The GitLab host requests go to."
  :type 'string)

(defcustom magit-glab-max-processes 4
  "How many glab processes may run at the same time."
  :type 'natnum)

(defcustom magit-glab-sync-timeout 30
  "Seconds a command waits for GitLab before giving up."
  :type 'natnum)

(defcustom magit-glab-log-max-lines 500
  "How many requests *magit-glab-log* keeps."
  :type 'natnum)

(cl-defstruct (magit-glab-request (:constructor magit-glab-request--create)
                                  (:copier nil))
  "One call of `magit-glab-api'."
  endpoint method params body paginate raw graphql callback errback start)

(defvar magit-glab-api-function #'magit-glab--api-glab
  "Function performing a `magit-glab-request'.
It must eventually call the request's callback or errback.  Tests replace
it with one that answers from fixtures.")

;;;; Requests

(defun magit-glab-default-errback (message)
  "Show MESSAGE, a failed request's error, in the echo area."
  (message "magit-glab: %s" message))

(cl-defun magit-glab-api (endpoint &key method params body paginate raw
                                   graphql callback errback)
  "Request ENDPOINT from GitLab's REST API, relative to /api/v4/.
PARAMS is an alist encoded into the query string.  BODY is a Lisp
object sent as JSON, for POST and PUT.  METHOD defaults to GET, or
POST when there is a BODY.  With PAGINATE, follow every page and
return one list of all items.  With RAW, return the response text
instead of parsing it as JSON.  GRAPHQL marks a GraphQL request, whose
errors come in a 200 response.

CALLBACK is called with the parsed response; ERRBACK, which defaults
to `magit-glab-default-errback', with a one-line error message."
  (funcall magit-glab-api-function
           (magit-glab-request--create
            :endpoint endpoint :method method :params params :body body
            :paginate paginate :raw raw :graphql graphql
            :callback (or callback #'ignore)
            :errback (or errback #'magit-glab-default-errback))))

(cl-defun magit-glab-graphql (query &key variables callback errback)
  "Run the GraphQL QUERY with VARIABLES, an alist.
CALLBACK gets the response's data object."
  (magit-glab-api "graphql"
                  :graphql t
                  :body `((query . ,query)
                          ,@(and variables `((variables . ,variables))))
                  :callback (lambda (response)
                              (funcall (or callback #'ignore)
                                       (alist-get 'data response)))
                  :errback errback))

(defun magit-glab-api-sync (endpoint &rest args)
  "Request ENDPOINT as `magit-glab-api' does, and wait for the answer.
ARGS are its keyword arguments, other than the callbacks.  Signal a
`user-error' if the request fails.  For interactive commands only:
never call this while a buffer is being refreshed."
  (let (done result failure)
    (apply #'magit-glab-api endpoint
           :callback (lambda (response) (setq result response done t))
           :errback (lambda (message) (setq failure message done t))
           args)
    (with-timeout (magit-glab-sync-timeout
                   (user-error "magit-glab: no answer from GitLab for %s" endpoint))
      (while (not done)
        (accept-process-output nil 0.05)))
    (when failure
      (user-error "magit-glab: %s" failure))
    result))

(defun magit-glab-graphql-sync (query &optional variables)
  "Run the GraphQL QUERY with VARIABLES and wait; return the data object."
  (alist-get 'data
             (magit-glab-api-sync "graphql" :graphql t
                                  :body `((query . ,query)
                                          ,@(and variables
                                                 `((variables . ,variables)))))))

(defun magit-glab-encode (string)
  "Encode STRING as one URL path segment, as project ids are."
  (url-hexify-string string))

;;;; The current user

(defvar magit-glab--user nil
  "The GitLab user glab is logged in as, as returned by GET /user.")

(defun magit-glab-current-user ()
  "Return the GitLab user glab is logged in as, asking GitLab once."
  (or magit-glab--user
      (setq magit-glab--user (magit-glab-api-sync "user"))))

(defun magit-glab-username ()
  "Return the username glab is logged in as."
  (alist-get 'username (magit-glab-current-user)))

;;;; Running glab

(defvar magit-glab--queue nil
  "Requests waiting for a glab process, oldest first.")

(defvar magit-glab--running 0
  "How many glab processes are running.")

(defun magit-glab--api-glab (request)
  "Queue REQUEST and start as many waiting requests as allowed."
  (setq magit-glab--queue (nconc magit-glab--queue (list request)))
  (magit-glab--dispatch))

(defun magit-glab--dispatch ()
  "Start queued requests while fewer than the maximum are running."
  (while (and magit-glab--queue
              (< magit-glab--running magit-glab-max-processes))
    (let ((request (pop magit-glab--queue)))
      (cl-incf magit-glab--running)
      (condition-case err
          (magit-glab--start request)
        (error
         (cl-decf magit-glab--running)
         (funcall (magit-glab-request-errback request)
                  (error-message-string err)))))))

(defun magit-glab--query-string (params)
  "Encode the alist PARAMS as a URL query string."
  (mapconcat (pcase-lambda (`(,key . ,value))
               (concat (url-hexify-string (format "%s" key)) "="
                       (url-hexify-string (format "%s" value))))
             params "&"))

(defun magit-glab--endpoint (request)
  "Return REQUEST's endpoint, with its parameters as the query string."
  (let ((endpoint (magit-glab-request-endpoint request))
        (params (magit-glab-request-params request)))
    (if params
        (concat endpoint (if (string-search "?" endpoint) "&" "?")
                (magit-glab--query-string params))
      endpoint)))

(defun magit-glab--arguments (request)
  "Return the glab arguments for REQUEST."
  (let ((body (magit-glab-request-body request))
        (method (magit-glab-request-method request)))
    `("api" "--hostname" ,magit-glab-host ,(magit-glab--endpoint request)
      ,@(cond (method (list "--method" method))
              ((and body (not (magit-glab-request-graphql request)))
               (list "--method" "POST")))
      ,@(and (magit-glab-request-paginate request)
             '("--paginate" "--output" "ndjson"))
      ;; glab 1.114 sends no body without the content type.
      ,@(and body '("--header" "Content-Type: application/json"
                    "--input" "-")))))

(defun magit-glab--program ()
  "Return the absolute file name of glab on this machine."
  (let ((exec-path (default-value 'exec-path)))
    (or (executable-find magit-glab-program)
        (error "Cannot find %s on this machine; see `magit-glab-program'"
               magit-glab-program))))

(defun magit-glab--json-string (object)
  "Return OBJECT serialized as JSON, as a multibyte string."
  (let ((json (json-serialize object)))
    (if (multibyte-string-p json)
        json
      (decode-coding-string json 'utf-8))))

(defun magit-glab--start (request)
  "Start a glab process for REQUEST."
  (let* ((default-directory (expand-file-name "~/"))
         (process-environment (default-value 'process-environment))
         (program (magit-glab--program))
         (out (generate-new-buffer " *magit-glab-out*" t))
         (err (generate-new-buffer " *magit-glab-err*" t))
         (process (make-process :name "magit-glab"
                                :buffer out
                                :stderr err
                                :command (cons program
                                               (magit-glab--arguments request))
                                :connection-type 'pipe
                                :coding 'utf-8
                                :noquery t
                                :sentinel #'magit-glab--sentinel)))
    (process-put process 'magit-glab-request request)
    (process-put process 'magit-glab-stderr err)
    (setf (magit-glab-request-start request) (current-time))
    (when-let* ((body (magit-glab-request-body request)))
      (process-send-string process (magit-glab--json-string body)))
    ;; Always close stdin, so glab never waits on it.
    (process-send-eof process)
    process))

(defun magit-glab--parse (request)
  "Parse the current buffer as the response to REQUEST."
  (goto-char (point-min))
  (let ((args '(:object-type alist :array-type list
                :null-object nil :false-object nil)))
    (cond ((magit-glab-request-raw request)
           (buffer-string))
          ((magit-glab-request-paginate request)
           ;; One JSON value per line, each an item of some page.
           (let (items)
             (while (progn (skip-chars-forward " \t\r\n") (not (eobp)))
               (push (apply #'json-parse-buffer args) items))
             (nreverse items)))
          ((progn (skip-chars-forward " \t\r\n") (eobp))
           nil)
          ((apply #'json-parse-buffer args)))))

(defun magit-glab--error-message (request status stdout stderr)
  "Return a one-line message for REQUEST failing with exit STATUS.
STDOUT and STDERR are what glab printed."
  (let* ((stderr (string-trim stderr))
         (detail (ignore-errors
                   (let ((response (json-parse-string
                                    stdout :object-type 'alist
                                    :null-object nil :false-object nil)))
                     (and (consp response)
                          (when-let* ((message (or (alist-get 'message response)
                                                   (alist-get 'error response))))
                            (if (stringp message)
                                message
                              (format "%S" message)))))))
         (first (car (split-string stderr "\n" t))))
    (cond ((or (string-match-p "401\\|[Nn]o token found\\|not authenticated" stderr)
               (equal detail "401 Unauthorized"))
           (format "glab is not logged in to %s; run `glab auth login --hostname %s'"
                   magit-glab-host magit-glab-host))
          ((string-join
            (delq nil (list (format "%s %s:" (magit-glab--method request)
                                    (magit-glab-request-endpoint request))
                            first
                            (and detail (not (and first (string-search detail first)))
                                 detail)
                            (and (not first) (not detail)
                                 (format "glab exited with %s" status))))
            " ")))))

(defun magit-glab--method (request)
  "Return the HTTP method REQUEST is sent with."
  (or (magit-glab-request-method request)
      (if (magit-glab-request-body request) "POST" "GET")))

(defun magit-glab--graphql-errors (response)
  "Return the error messages of a GraphQL RESPONSE joined, or nil."
  (when-let* ((errors (and (listp response) (alist-get 'errors response))))
    (mapconcat (lambda (error) (or (alist-get 'message error) (format "%S" error)))
               errors "; ")))

(defun magit-glab--sentinel (process _event)
  "Finish PROCESS once glab has exited: parse, log, and call back."
  (unless (process-live-p process)
    (let* ((request (process-get process 'magit-glab-request))
           (out (process-buffer process))
           (err (process-get process 'magit-glab-stderr))
           (status (process-exit-status process))
           (pipe (get-buffer-process err))
           outcome)
      ;; stderr arrives through a pipe process of its own, which may still
      ;; have output buffered when glab's exit is reported.
      (when pipe
        (let ((tries 20))
          (while (and (> tries 0) (process-live-p pipe)
                      (accept-process-output pipe 0.05))
            (cl-decf tries))))
      (cl-decf magit-glab--running)
      (unwind-protect
          (let ((stdout (with-current-buffer out (buffer-string)))
                (stderr (with-current-buffer err (buffer-string))))
            (setq outcome
                  (if (/= status 0)
                      (list :error (magit-glab--error-message
                                    request status stdout stderr))
                    (condition-case parse-error
                        (let ((response (with-current-buffer out
                                          (magit-glab--parse request))))
                          (if-let* ((errors (and (magit-glab-request-graphql request)
                                                 (magit-glab--graphql-errors response))))
                              (list :error (format "GraphQL: %s" errors))
                            (list :ok response)))
                      (error (list :error (format "%s: cannot parse the response: %s"
                                                  (magit-glab-request-endpoint request)
                                                  (error-message-string parse-error)))))))
            (magit-glab--log request status))
        (kill-buffer out)
        (kill-buffer err)
        (magit-glab--dispatch))
      (pcase outcome
        (`(:ok ,response)
         (magit-glab--call (magit-glab-request-callback request) response))
        (`(:error ,message)
         (magit-glab--call (magit-glab-request-errback request) message))))))

(defun magit-glab--call (function argument)
  "Call FUNCTION with ARGUMENT, reporting an error instead of losing it."
  (condition-case err
      (funcall function argument)
    (error (message "magit-glab: %s" (error-message-string err)))))

;;;; The log

(defun magit-glab--log (request status)
  "Record REQUEST, which glab finished with exit STATUS, in the log buffer."
  (with-current-buffer (get-buffer-create "*magit-glab-log*")
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "%s %5dms %s %-6s %s%s\n"
                      (format-time-string "%T")
                      (round (* 1000 (float-time
                                      (time-subtract nil (magit-glab-request-start
                                                          request)))))
                      (if (= status 0) "ok  " (format "E%-3d" status))
                      (magit-glab--method request)
                      (magit-glab--endpoint request)
                      (if (magit-glab-request-paginate request) " (all pages)" "")))
      (let ((excess (- (count-lines (point-min) (point-max))
                       magit-glab-log-max-lines)))
        (when (> excess 0)
          (goto-char (point-min))
          (forward-line excess)
          (delete-region (point-min) (point))))
      (setq buffer-read-only t))))

;;;###autoload
(defun magit-glab-show-log ()
  "Show the log of glab requests."
  (interactive)
  (display-buffer (get-buffer-create "*magit-glab-log*")))

(provide 'magit-glab-api)
;;; magit-glab-api.el ends here
