;;; write-subdirs-el.el --- Create subdirs.el files

;; Copyright (C) 2000 by Tom Breton

;; Author: Tom Breton <tob@world.std.com>
;; Keywords: local
;; Version 1.2

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; This code creates subdirs.el files for directory trees.

;;; Motivation

;; Why do that, you ask?  By way of explanation, subdirectories of
;; site-lisp automatically become part of the load-path when you start
;; Emacs.  That makes site-lisp an appealing place to put Elisp
;; packages.

;; But there is more subdirs.el could do for you.  For instance, it
;; could set up Info-default-directory-list and autoloads.

;; As I write this, package maintainers generally don't use
;; subdirs.el.  Perhaps they mostly don't know about it.  I hope
;; write-subdirs-el will help change that.

;; I have a vision of a thousand elisp packages that require no more
;; setup than being placed in site-lisp.  (And sometimes a
;; command-line "make").  And I imagine a thousand package maintainers
;; who can provide easy installation for their users with little or no
;; more work then typing M-x tehom-wse-entry.

;;; Installation:

;; Place write-subdirs-el anywhere in your load-path

;; IMPORTANT: Replace your existing site-lisp/subdirs.el with
;; new-subdirs-el.el.  That is, put site-lisp/subdirs.el somewhere
;; safe and rename new-subdirs-el.el to that. If you use the old
;; version and build subdirs.els with this package, some directory
;; trees (those that have no Elisp code in their root directories, but
;; do have Elisp in their subdirectories) will be unexpectedly omitted
;; from load-path.

;; If you can't load a subdirs.el that's not hanging off site-lisp,
;; it's a known bug that's fixed by new-subdirs-el.el

;;; Customizations:

;; If you want it to generate autoloads, customize
;; tehom-wse-do-autoloads-p to t.

;; WARNING: If the autoloads don't work, emacs won't start.  That's
;; not under my control, it's up to the maintainers of the individual
;; packages,

;;; Entry points:

;; IMPORTANT: You will need to have read and write permissions to all
;; the directories in question.  If not, nothing will happen.

;; tehom-wse-do-all-dirs-in-site-lisp will tackle every single
;; directory in site-lisp in one command.  You'll probably want to run
;; this exactly once.

;; tehom-wse-make-subdirs-el will make subdirs.el for any given
;; directory tree.

;; tehom-wse-entry will make a subdirs.el for a directory in your
;; load-path.  It's a little more convenient than navigating your
;; load-path manually.

;;; Testing

;; This has not been easy to test.  Testing it properly requires
;; dealing with a whole test directory structure.  The standard elisp
;; distribution directory could perhaps be used, but mine is
;; non-standard.  I could create a whole directory tree, but that's a
;; lot of work just to test one part of this.  Testing it properly
;; also requires starting emacs a lot of times.  I've done that to a
;; degree, but obviously automated testing was out of the question.

;; So while I've given it what testing I could, there's a bit of a
;; cross-your-fingers-and-hope factor.  PLEASE inspect any subdirs.el
;; it writes and if there are obvious problems, don't use it.  (ie,
;; move it somewhere out of your load-path)

;; IMPORTANT: At worst, your system can be restored to the way it was
;; by restoring your old site-lisp/subdirs.el and erasing any
;; subdirs.el and .nosearch files in site-lisp's subdirectories.  I
;; don't think that will ever be neccessary, but I wanted to point it
;; out just in case.

;;; Non-features:

;; If a subdirectory being examined itself contains a subdirs.el, that
;; directory could be handled by a call to that file, nothing more.
;; NB we'd have to exclude the directory tree root from this,
;; otherwise we could possibly call our file itself in an infinite
;; loop.  This probably isn't worth doing, because no packages are so
;; deep they would get any use out of nested subdirs.el's

;; Changelog:

;; Version 1.2: Provided code in new-subdirs-el.el to get around
;; startup's inability to handle working from directories that aren't
;; already in load-path.

;; Version 1.1: Fixed the bug where Info-path was sometimes missed.
;; Changed the output to add some appropriate local variables
;; including no-update-autoloads.

;;; Code:

(require 'cl)
(require 'autoload)

;;;;

(defcustom tehom-wse-do-autoloads-p nil  
  "Do autoloads"
  :type 'boolean)


;;;; Constants

(defconst tehom-wse-filename "subdirs.el" "" )
(defconst tehom-directory-meanings-alist
  '(
     ("lisp"    . lisp)
     ("contrib" . lisp)
     ("info"    . info)
     ("texi"    . info)
     ("texinfo" . info))
  "The meanings of canonical directory names." )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Helper functions:

;;Helpers for entry points

(defun tehom-wse-get-load-path-matching (regex)
  "Return a list of names in load-path that match REGEX."

  (loop 
    for dir-name in load-path
    if 
    (string-match regex dir-name)
    collect dir-name))

;;Helpers for command functions

(defun tehom-force-file-to-exist (filename)
  ""

  (unless
    (file-exists-p filename)
    (write-region "" nil filename)))


(defun tehom-remove-file-if-exists (filename)
  ""
  (if
    (file-exists-p filename)
    (delete-file filename)))


;;Helpers for collector functions.

(defun tehom-filter-strings-matching (string-list regex)
  "Return a list of strings in STRING-LIST matching REGEX."
    
  (loop
    for string in string-list
    if
    (string-match regex string)
    collect string))


(defun tehom-any-elisp (filename-list)
  "Return non-nil if any names in FILENAME-LIST look like Elisp executables.

subdirs.el itself doesn't count."
  
  (let* 
    ;;Don't let subdirs.el make a directory look like it has Elisp.
    ((filename-list-1
       (remove* "subdirs.el" filename-list :test #'string= )))
  
    (tehom-filter-strings-matching filename-list-1 "\\.elc?\\'")))

;;Finding info files is iffy, but we do our best.
(defun tehom-any-info-files (filename-list)
  "Return non-nil if any names in FILENAME-LIST look like info files."
  (or
    (tehom-filter-strings-matching filename-list "\\.info?\\'")
    (tehom-filter-strings-matching filename-list "\\-[0-9]+\\'")))


;;Used to collect source files for autoloads
(defun tehom-collect-elisp-sources (filename-list)
  "Return the names from FILENAME-LIST that look like Elisp source code."

  (let* 
    ;;Don't treat subdirs.el like normal source, nor the temp files
    ;;emacs makes for the open subdirs.el files.
    ((filename-list-1
       (remove* "subdirs.el$" filename-list :test #'string-match )))
  
    (tehom-filter-strings-matching filename-list-1 "\\.el\\'")))


;;Borrowed from startup.el and encapsulated.
(defun tehom-wse-name-is-nice-directory (name)
  "Return non-nil if NAME looks like a nice directory.

Nice here means that its name strts with an alphanumeric character and
it doesn't look like Elisp code."

  (and 
    (string-match "\\`[a-zA-Z0-9]" name)
    ;; Avoid doing a `stat' when it isn't necessary
    ;; because that can cause trouble when an NFS server
    ;; is down.
    (not (string-match "\\.elc?\\'" name))
    (file-directory-p name)))


;;tehom-wse-name-is-nice-directory needs to test base-names, but
;;tehom-wse-collect-nice-subdirectories needs to return multi-component
;;relative names.  So be very careful about how we treat expansion.
(defun tehom-wse-collect-nice-subdirectories (directory)
  "Collect all \"nice\" subdirectories of DIRECTORY.

DIRECTORY is relative to default-directory."
  
  (let*
    (
      ;;Generate base-names.
      (filename-list (directory-files directory nil nil t))
      ;;Still all base-names
      (stripped-list
	(remove-if-not #'tehom-wse-name-is-nice-directory filename-list)))

    (mapcar
      ;;Expand each name wrt DIRECTORY, then make it relative to the
      ;;top directory.
      #'(lambda (base-name)
	  (file-relative-name (expand-file-name base-name directory)))
      
      stripped-list)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Path collector functions

(defun tehom-wse-examine-homogeneous-subdirectories (directory type)
  "Examine DIRECTORY and its subdirectories, treating TYPE as unchanging."
  
  (dolist
    (subdirectory 
      (tehom-wse-collect-nice-subdirectories directory))
	    
    (tehom-wse-examine-directory subdirectory type)))

(defun tehom-wse-examine-directory (directory type)
  "Examine DIRECTORY and its subdirectories, according to TYPE."

  
  (let
    ((filename-list (directory-files directory)))
    (declare (special add-to-load-path add-to-info-path))

    (case type

      ('lisp
	(push directory add-to-load-path)
	;;Treat all its subdirectories as lisp.
	(tehom-wse-examine-homogeneous-subdirectories directory 'lisp))
      

      ('info
	(push directory add-to-info-path)
	;;Treat all its subdirectories as info.
	(tehom-wse-examine-homogeneous-subdirectories directory 'info))
      

      ('unclassified

	;;Try all the possibilities.  More than one can be used.
	(if
	  (tehom-any-elisp filename-list)
	  (push directory add-to-load-path))
	  
	(if
	  (tehom-any-info-files filename-list)
	  (push directory add-to-info-path))
	
	;;Recurse into each subdirectory.
	(dolist
	  (subdirectory 
	    (tehom-wse-collect-nice-subdirectories directory))
	    
	  (let
	    ;;Classify the subdirectory if possible.
	    ((subdirectory-type
	       (or
		 (cdr-safe 
		   (assoc subdirectory
		     tehom-directory-meanings-alist))
		 'unclassified)))
	
	    (tehom-wse-examine-directory subdirectory subdirectory-type)))

	))))


;;Manages the special variables add-to-load-path and add-to-info-path
(defun tehom-wse-examine-directory-tree ()
  "Return what directories to add to load-path and to info path."
  
  (let
    (
      (add-to-load-path '())
      (add-to-info-path '()))
    
    (declare (special add-to-load-path add-to-info-path))
    
    (tehom-wse-examine-directory "." 'unclassified)

    (values add-to-load-path add-to-info-path)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Output functions

(defun tehom-wse-insert-all 
  (add-to-load-path add-to-info-path make-autoloads-list)
  ""
  
  (insert

      ";;
;; subdirs.el
;; Generated on "
    (format-time-string "%a %e %b, %Y %l:%M %p")
    " by "
    (user-full-name)
    "
;; By write-subdirs-el, written by Tehom (Tom Breton)
;;

"
      
      
    )
  
  (if
    (not
      (or 
	add-to-load-path add-to-info-path make-autoloads-list))
    (insert ";;Nothing to do\n")
    (progn
      (tehom-wse-insert-load-path add-to-load-path)
      (tehom-wse-insert-info-path add-to-info-path)
      (tehom-wse-insert-autoloads make-autoloads-list)))

  (insert
    "
;; Local Variables:
;; version-control: never
;; no-byte-compile: t
;; no-update-autoloads: t
;; End:
"
    ))





(defun tehom-wse-insert-load-path (add-to-load-path)
  "Insert Elisp code to add the list ADD-TO-LOAD-PATH to load-path."

  (when add-to-load-path
    (pp
      `(normal-top-level-add-to-load-path ',add-to-load-path)
      (current-buffer))))

(defun tehom-wse-insert-info-path (add-to-info-path)
  "insert Elisp code to add the list ADD-TO-INFO-PATH to info path."

  (dolist (path add-to-info-path)
    (pp
      `(add-to-list 'Info-default-directory-list 
	 (expand-file-name ,path))
      (current-buffer))))

(defun tehom-wse-insert-autoloads (add-to-load-path)
  "Insert autoloads."
  
  (dolist
    (path add-to-load-path)
    
    (let* 
      ((expanded (expand-file-name path)))
      (dolist
	(source-file
	  (tehom-collect-elisp-sources 
	    (directory-files expanded)))
      
	(generate-file-autoloads 
	  (expand-file-name source-file expanded))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Managing function


(defun tehom-wse-write-subdirs-el ()
  "Write subdirs.el code into the current buffer.

Also manage the existence of `.nosearch'."
  
  (multiple-value-bind
    (add-to-load-path add-to-info-path)
    (tehom-wse-examine-directory-tree)
    
    (let
      (
	(nosearch-filename ".nosearch")
	(loads-own-directory-p 
	  (find "." add-to-load-path  :test #'string=))

	(make-autoloads-list
	  (if tehom-wse-do-autoloads-p
	    add-to-load-path
	    nil)))

      ;;.nosearch, not subdirs.el, will indicate whether to put this
      ;;directory itself on load-path.  So we remove "." if it was
      ;;there, and in either case we set .nosearch accordingly.
      ;;But we mustn't omit that from autoloads. 
      (if
	loads-own-directory-p
	(progn
	  (setq add-to-load-path 
	    (remove* "." add-to-load-path :test #'string= ))
	  (tehom-remove-file-if-exists nosearch-filename))
	(tehom-force-file-to-exist nosearch-filename))

      (erase-buffer)
      (tehom-wse-insert-all 
	add-to-load-path add-to-info-path make-autoloads-list))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Entry points

;;;###autoload
(defun tehom-wse-make-subdirs-el 
  (directory &optional force-autoloads force)
  "Make a subdirs.el file for the given directory tree."

  (interactive "DMake subdirs.el in which directory? \nP")

  (unless
    (string= directory "")

    (let*
      ( (default-directory directory)
	(tehom-wse-do-autoloads-p 
	  (or tehom-wse-do-autoloads-p force-autoloads))
	(proceed
	  (or
	    force
	    (not (file-exists-p tehom-wse-filename)))))
    
      (save-excursion
	(when
	  proceed
	  (find-file tehom-wse-filename)
	  (tehom-wse-write-subdirs-el)
	  (save-buffer))))))


;;;###autoload
(defun tehom-wse-make-subdirs-el-force (directory &optional force-autoloads)
  ""
  (interactive "DMake subdirs.el in which directory? \nP")
  (tehom-wse-make-subdirs-el directory force-autoloads t))

;;;###autoload
(defun tehom-wse-entry (&optional force-autoloads)
  "Call tehom-wse-make-subdirs-el with a directory from load-path."
  
  (interactive "P")
  (let*
    ((directory 
       (completing-read "Pick one: " 
	 (mapcar #'list load-path))))

    (unless 
      (string= directory "")

      (tehom-wse-make-subdirs-el directory force-autoloads))))



;; It wouldn't be hard to make another entry point to pick exactly
;; subdirectories of site-lisp, if that proves more useful than
;; tehom-wse-entry.  Just use completing-read on:
;; (tehom-wse-get-load-path-matching "site-lisp\.[^/]+$")


(defun tehom-wse-do-all-dirs-in-site-lisp (&optional force)
  "Make subdirs.el for every immediate subdirectory of site-lisp.
If there is more than one */site-lisp in load-path, prompt for which
one to use.

This calls tehom-wse-make-subdirs-el on every immediate subdirectory
of site-lisp."
  
  (interactive "P")
  (let*
    (
      (potential-site-lisp-roots
	(tehom-wse-get-load-path-matching "site-lisp$"))
      
      (site-lisp-root 
	(case (length potential-site-lisp-roots)
	  (0 "")
	  (1 (car potential-site-lisp-roots))
	  (t
	    (completing-read "Which site-lisp: " 
	      (mapcar #'list potential-site-lisp-roots))))))
    
    (unless (string= site-lisp-root "")

      (let* 
	( ;;Important: Bind default-directory around this list-form
	  (default-directory site-lisp-root)
	  (directories 
	    (tehom-wse-collect-nice-subdirectories ".")))
	
	(dolist
	  (base-directory-name directories)
	  
	  (let 
	    ((directory 
	       (expand-file-name base-directory-name)))

	    (tehom-wse-make-subdirs-el directory force)))))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Design notes:

;;Overview

;;First stage:  Crawl thru directories, collecting paths
;;Second stage: Output what we have.
;;Third stage:  When emacs starts up, the subdirs.els will get run.

;;;;
;;What we look for when examining directories

;;Directories are classified either according to their contents or
;;according to their name.

;;Look for .el and .elc files.  If seen, the directory contains Elisp
;;(and maybe more)

;;Look for files ending in .info or -[0-9]+ and consider them info
;;files.  If seen, the directory contains info (and maybe more)

;;Look for a "lisp" or "contrib" subdirectories and treat them as
;;containing all Elisp

;;Look for "info", "texi", "texinfo" subdirectories and treat them as
;;containing all info

;;Simply recurse into other directories.

;;;;;;;

;;The returned paths should always be relative to the starting
;;directory.  That way the directory-tree can be moved around without
;;consequence, and maintainers can generate a subdirs.el without
;;knowing the layout of the target directory structure.

;;;;;;;
;;What to write in subdirs.el

;;Write additions to load-path.
;;Write additions to Info-default-directory-list
;;Make autoloads for all .el files in any directory we're adding to
;;load-path.

;;;;;;;
;;normal-top-level-add-subdirs-to-load-path (Not here, but important)

;; normal-top-level-add-subdirs-to-load-path adds dirs as they come
;; off the pending list.  dirs with subdirs.el could
;; a) add themselves, but not be pending.  Wrong, because they
;; themselves may not want to be part of load-path.

;; b) execute the subdirs.el directly.  This may cause subdirs.el to
;; be executed twice, once by this, once when found in load-path.

;; c) execute it only if it's not going to be executed later, meaning
;; if it's not being put in load-path.  Trust subdirs.el to not cause
;; itself problems by (wrong if .nosearch exists) putting its own
;; directory in load-path.

;;End design notes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; write-subdirs-el.el ends here