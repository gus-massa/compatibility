
(module sigutil mzscheme
  ;; Used by signedunit.ss 

  (import "sigmatch.ss")
  (import "exstruct.ss")

  (define-struct signature (name    ; sym
			    src     ; sym
			    elems)) ; list of syms and signatures
  (define-struct parse-unit (imports renames vars body))

  (define-struct/export sig (content))

  (define inline-sig-name '<unnamed>)

  (define-syntax literal?
    (lambda (expr)
      (syntax-case expr ()
	[(_ a)
	 (syntax (eq? (syntax-e (syntax a)) 'a))])))

  (define (stx->sym s)
    (if (syntax? s) (syntax-e s) s))

  (define syntax-error
    (case-lambda 
     [(who expr msg sub)
      (raise-syntax-error who msg expr sub)]
     [(who expr msg)
      (raise-syntax-error who msg expr)]))

  (define undef-sig-error
    (lambda (who expr what)
      (syntax-error who expr 
		    "signature not defined"
		    what)))

  (define not-a-sig-error
    (lambda (who expr what)
      (syntax-error who expr 
		    "not a signature"
		    what)))

  (define rename-signature
    (lambda (sig name)
      (make-signature name 
		      (signature-src sig) 
		      (signature-elems sig))))

  (define intern-signature
    (lambda (name desc error)
      (make-signature
       name
       name
       (if (vector? desc)
	   (map
	    (lambda (elem)
	      (cond
	       [(symbol? elem) elem]
	       [(and (pair? elem) (symbol? (car elem)))
		(intern-signature (car elem) (cdr elem) error)]
	       [else (error)]))
	    (vector->list desc))
	   (error)))))

  (define get-sig
    (lambda (who expr name sigid)
      (if (not (identifier? sigid))
	  (parse-signature who expr 
			   (if name
			       name
			       inline-sig-name)
			   sigid)
	  (let ([v (syntax-local-value sigid (lambda () #f))])
	    (unless v
	      (undef-sig-error who expr sigid))
	    (unless (sig? v)
	      (not-a-sig-error who expr sigid))
	    (let ([s (intern-signature (syntax-e sigid) (sig-content v)
				       (lambda ()
					 (not-a-sig-error who expr sigid)))])
	      (if name
		  (rename-signature s (stx->sym name))
		  s))))))

  (define check-unique
    (lambda (names error-k)
      (let ([dup (check-duplicate-identifier 
		  (map (lambda (n)
			 (if (syntax? n)
			     n
			     (datum->syntax n #f #f)))
		       names))])
	(when dup
	  (error-k dup)))))

  (define build-struct-names
    (lambda (name-stx fields omit-sel? omit-set?)
      (let ([name (symbol->string (syntax-e name-stx))]
	    [fields (map symbol->string (map syntax-e fields))]
	    [+ string-append])
	(map (lambda (s)
	       (datum->syntax (string->symbol s) #f name-stx))
	     (append
	      (list 
	       (+ "make-" name)
	       (+ name "?")
	       (+ "struct:" name))
	      (if omit-sel?
		  null
		  (map
		   (lambda (f)
		     (+ name "-" f))
		   fields))
	      (if omit-set?
		  null
		  (map
		   (lambda (f)
		     (+ "set-" name "-" f "!"))
		   fields)))))))

  (define parse-signature
    (lambda (who expr name body)
      (let ([elems
	     (let loop ([body body])
	       (syntax-case body ()
		 [() null]
		 [(something . rest)
		  (append
		   (syntax-case (syntax something) ()
		     [:
		      (literal? :)
		      (syntax-error who expr
				    "misplaced `:'"
				    (syntax something))]
		     [id
		      (identifier? (syntax id))
		      (list (syntax id))]
		     [(struct name (field ...) omission ...)
		      (literal? struct)
		      (let ([name (syntax name)]
			    [fields (syntax->list (syntax (field ...)))]
			    [omissions (syntax->list (syntax (omission ...)))])
			(unless (identifier? (syntax name))
			  (syntax-error who expr
					"struct name is not an identifier"
					name))
			(for-each
			 (lambda (fld)
			   (unless (identifier? fld)
			     (syntax-error who expr
					   "field name is not an identifier"
					   fld)))
			 fields)
			(let-values ([(omit-names
				       omit-setters?
				       omit-selectors?)
				      (let loop ([omissions omissions]
						 [names null]
						 [no-set? #f]
						 [no-sel? #f])
					(if (null? omissions)
					    (values names no-set? no-sel?)
					    (let ([rest (cdr omissions)])
					      (syntax-case (car omissions) (-selectors
									    -setters
									    -)
						[-selectors
						 (loop rest names #t no-sel?)]
						[-setters
						 (loop rest names no-set? #t)]
						[(- name)
						 (identifier? (syntax name))
						 (loop rest (cons (syntax name) names)
						       no-set? no-sel?)]
						[else
						 (syntax-error who expr
							       "bad struct omission"
							       (car omissions))]))))])
			  (letrec ([names (build-struct-names 
					   name fields 
					   omit-selectors? omit-setters?)]
				   [filter
				    (lambda (names)
				      (cond
				       [(null? names) null]
				       [(ormap (lambda (x) (eq? (syntax-e (car names))
								(syntax-e x)))
					       omit-names)
					(filter (cdr names))]
				       [else (cons (car names) (filter (cdr names)))]))])
			    (if (null? omit-names)
				names 
				(filter names)))))]
		     [(struct . _)
		      (literal? struct)
		      (syntax-error who expr
				    "bad `struct' clause form"
				    (syntax something))]
		     [(unit name : sig) 
		      (and (literal? unit)
			   (identifier? (syntax name)))
		      (let ([s (get-sig who expr (syntax name) (syntax sig))])
			(list s))]
		     [(unit . _)
		      (literal? unit)
		      (syntax-error who expr 
				    "bad `unit' clause form"
				    (syntax something))]
		     [(open sig)
		      (literal? open)
		      (let ([s (get-sig who expr #f (syntax sig))])
			(signature-elems s))]
		     [(open . _)
		      (literal? open)
		      (syntax-error who expr 
				    "bad `open' clause form"
				    (syntax something))]
		     [else
		      (syntax-error who expr "improper signature clause type"
				    (syntax something))])
		   (loop (syntax rest)))]
		 [_else (syntax-error who expr "illegal use of `.'")]))])
	(check-unique (map
		       (lambda (elem)
			 (cond
			  [(symbol? elem) elem]
			  [(identifier? elem) (syntax-e elem)]
			  [else (signature-name elem)]))
		       elems)
		      (lambda (name)
			(syntax-error who expr
				      "duplicate name in signature"
				      name)))
	(make-signature (stx->sym name)
			(stx->sym name)
			(sort-signature-elems
			 (map (lambda (id)
				(if (identifier? id)
				    (syntax-e id)
				    id))
			      elems))))))

  (define explode-sig
    (lambda (sig)
      (list->vector
       (map 
	(lambda (v)
	  (if (symbol? v)
	      v
	      (cons
	       (signature-name v)
	       (explode-sig v))))
	(signature-elems sig)))))

  (define explode-named-sig
    (lambda (s)
      (cons
       (cond
	[(signature-name s)]
	[(signature-src s)]
	[else inline-sig-name])
       (explode-sig s))))

  (define explode-named-sigs
    (lambda (sigs)
      (map explode-named-sig sigs)))

  (define sort-signature-elems
    (lambda (elems)
      (letrec ([split
		(lambda (l f s)
		  (cond
		   [(null? l) (values f s)]
		   [(null? (cdr l)) (values (cons (car l) f) s)]
		   [else (split (cddr l) (cons (car l) f) (cons (cadr l) s))]))]
	       [merge
		(lambda (f s)
		  (cond
		   [(null? f) s]
		   [(null? s) f]
		   [(less-than? (car s) (car f))
		    (cons (car s) (merge f (cdr s)))]
		   [else
		    (cons (car f) (merge (cdr f) s))]))]
	       [less-than?
		(lambda (a b)
		  (if (symbol? (car a))
		      (if (symbol? (car b))
			  (string<? (cdr a) (cdr b))
			  #t)
		      (if (symbol? (car b))
			  #f
			  (string<? (cdr a) (cdr b)))))]
	       [pair
		(lambda (i)
		  (cons i (symbol->string (if (symbol? i) i (signature-name i)))))])
	(map car
	     (let loop ([elems (map pair elems)])
	       (cond
		[(null? elems) null]
		[(null? (cdr elems)) elems]
		[else (let-values ([(f s) (split elems null null)])
				  (merge (loop f) (loop s)))]))))))
		   
  (define flatten-signature
    (lambda (id sig)
      (apply
       append
       (map
	(lambda (elem)
	  (if (symbol? elem)
	      (list
	       (if id
		   (string->symbol (string-append id ":" (symbol->string elem)))
		   elem))
	      (flatten-signature (let* ([n (signature-name elem)]
					[s (if n
					       (symbol->string n)
					       #f)])
				   (if (and id s)
				       (string-append id ":" s)
				       (or id s)))
				 elem)))
	(signature-elems sig)))))

  (define flatten-signatures
    (lambda (sigs)
      (apply append (map (lambda (s) 
			   (let* ([name (signature-name s)]
				  [id (if name
					  (symbol->string name)
					  #f)])
			     (flatten-signature id s)))
			 sigs))))

  (define signature-parts
    (lambda (q?)
      (lambda (sig)
	(let loop ([elems (signature-elems sig)])
	  (cond
	   [(null? elems) null]
	   [(q? (car elems)) (cons (car elems) (loop (cdr elems)))]
	   [else (loop (cdr elems))])))))
  (define signature-vars (signature-parts symbol?))
  (define signature-subsigs (signature-parts signature?))

  (define do-rename
    (lambda (export-name renames)
      (let loop ([renames renames])
	(cond
	 [(null? renames) export-name]
	 [(eq? (cadar renames) export-name)
	  (caar renames)]
	 [else (loop (cdr renames))]))))
      
  (define check-signature-unit-body
    (lambda (sig a-unit renames who expr)
      (let ([vars (map syntax-e (parse-unit-vars a-unit))])
	(for-each
	 (lambda (var)
	   (let ([renamed (do-rename var renames)])
	     (unless (memq renamed vars)
		     (syntax-error who expr
				   (format 
				    "signature \"~s\" requires variable \"~s\"~a"
				    (signature-src sig)
				    var
				    (if (eq? var renamed)
					""
					(format " renamed \"~s\"" renamed)))))))
	 (signature-vars sig))
	(unless (null? (signature-subsigs sig))
		(syntax-error who expr
			      (format 
			       "signature \"~s\" requires sub-units"
			       (signature-src sig)))))))

  (define parse-imports
    (lambda (who untagged-legal? really-import? expr clause)
      (let ([bad
	     (lambda (why . rest)
	       (apply
		syntax-error who expr 
		(format (if really-import?
			    "bad `import' clause~a" 
			    "bad linkage specification~a")
			why)
		rest))])
	(let ([clause (stx->list clause)])
	  (unless (stx-list? clause)
	    (bad ""))
	  (map
	   (lambda (item)
	     (syntax-case item ()
	       [id 
		(and (identifier? (syntax id))
		     untagged-legal?)
		(rename-signature (get-sig who expr #f item) #f)]
	       [(id : sig)
		(and (identifier? (syntax id))
		     (eq? (syntax-e (syntax :)) ':))
		(get-sig who expr (syntax id) (syntax sig))]
	       [any
		untagged-legal?
		(rename-signature (get-sig who expr #f item) #f)]
	       [_else
		(bad "" item)]))
	   clause)))))

  (define parse-unit
    (lambda (expr body sig user-stx-forms dv-stx begin-stx inc-stx)
      (let ([body (stx->list body)])
	(unless body
	  (syntax-error 'unit/sig expr "illegal use of `.'"))
	(unless (and (pair? body)
		     (stx-pair? (car body))
		     (eq? 'import (syntax-e (stx-car (car body)))))
	  (syntax-error 'unit/sig expr 
			"expected `import' clause"))
	(let* ([imports (parse-imports 'unit/sig #t #t expr (stx-cdr (car body)))]
	       [imported-names (flatten-signatures imports)]
	       [exported-names (flatten-signature #f sig)]
	       [body (cdr body)])
	  (let-values ([(renames body)
			(if (and (stx-pair? body)
				 (stx-pair? (car body))
				 (eq? 'rename (syntax-e (stx-car (car body)))))
			    (values (map syntax->datum (cdr (stx->list (car body)))) (cdr body))
			    (values null body))])
	    (unless renames
	      (syntax-error 'unit/sig expr "illegal use of `.'" (car body)))
	    ;; Check renames:
	    (let ([bad
		   (lambda (why sub)
		     (syntax-error 'unit/sig expr 
				   (format "bad `rename' clause~a" why)
				   sub))])
	      (for-each
	       (lambda (id)
		 (syntax-case id ()
		   [(iid eid)
		    (begin
		      (unless (identifier? (syntax iid))
			(bad ": original name is not an identifier" (syntax iid)))
		      (unless (identifier? (syntax eid))
			(bad ": new name is not an identifier" (syntax eid))))]
		   [else
		    (bad "" id)]))
	       renames))
	    (check-unique (map car renames)
			  (lambda (name)
			    (syntax-error 'unit/sig expr
					  "id renamed twice"
					  name)))
	    (let* ([renamed-internals (map car renames)]
		   [swapped-renames (map (lambda (s) (cons (cadr s) (car s))) renames)]
		   [filtered-exported-names 
		    (if (null? renames) ;; an optimization
			exported-names
			(let loop ([e exported-names])
			  (if (null? e)
			      e
			      (if (ormap (lambda (rn) (eq? (car rn) (car e))) 
					 swapped-renames)
				  (loop (cdr e))
				  (cons (car e) (loop (cdr e)))))))]
		   [local-vars (append renamed-internals filtered-exported-names imported-names)])
	      (let loop ([pre-lines null][lines body][port #f][port-name #f][body null][vars null])
		(cond
		 [(and (null? pre-lines) (not port) (null? lines))
		  (make-parse-unit imports renames vars body)]
		 [(and (null? pre-lines) (not port) (not (pair? lines)))
		  (syntax-error 'unit/sig expr "improper body list form")]
		 [else
		  (let-values ([(line) (let ([s (cond
						 [(pair? pre-lines) (car pre-lines)]
						 [port (read-syntax port-name port)]
						 [else (car lines)])])
					 (if (eof-object? s)
					   s
					   (local-expand s    
							 (append
							  user-stx-forms
							  local-vars))))]
			       [(rest-pre-lines) 
				(if (null? pre-lines)
				    null
				    (cdr pre-lines))]
			       [(rest-lines)
				(if (and (null? pre-lines) (not port))
				    (cdr lines)
				    lines)])
		    (cond
		     [(and (null? pre-lines) 
			   port
			   (eof-object? line))
		      (values lines body vars)]
		     [(and (stx-pair? line)
			   (module-identifier=? (stx-car line) dv-stx))
		      (syntax-case line ()
			[(_ (id ...) expr)
			 (loop rest-pre-lines
			       rest-lines
			       port
			       port-name
			       (cons line body)
			       (append (syntax->list (syntax (id ...))) vars))]
			[else
			 (syntax-error 'unit/sig expr 
				       "improper `define-values' clause form"
				       line)])]
		     [(and (stx-pair? line)
			   (module-identifier=? (stx-car line) begin-stx))
		      (let ([line-list (stx->list line)])
			(unless line-list
			  (syntax-error 'unit/sig expr 
					"improper `begin' clause form"
					line))
			(loop (append (cdr line-list) rest-pre-lines)
			      rest-lines
			      port
			      port-name
			      body
			      vars))]
		     [(and (stx-pair? line)
			   (module-identifier=? (stx-car line) inc-stx))
		      (syntax-case line ()
			[(_ filename)
			 (string? (syntax-e (syntax filename)))
			 (let ([file (syntax-e (syntax filename))])
			   (let-values ([(base name dir?) (split-path file)])
			     (when dir?
			       (syntax-error 'unit/sig expr 
					     (format "cannot include a directory ~s"
						     file)))
			     (let* ([old-dir (current-load-relative-directory)]
				    [c-file (if (and old-dir (not (complete-path? file)))
						(path->complete-path file old-dir)
						file)]
				    [p (open-input-file c-file)])
			       (let-values ([(lines body vars)
					     (parameterize ([current-load-relative-directory
							     (if (string? base) 
								 (if (complete-path? base)
								     base
								     (path->complete-path 
								      base
								      (or old-dir 
									  (current-directory))))
								 (or old-dir
								     (current-directory)))])
					       (dynamic-wind
						void
						(lambda ()
						  (loop null
							rest-lines
							p
							c-file
							body
							vars))
						(lambda ()
						  (close-input-port p))))])
				 (loop rest-pre-lines lines port port-name body vars)))))]
			[else
			 (syntax-error 'unit/sig expr 
				       "improper `include' clause form"
				       line)])]
		     [else
		      (loop rest-pre-lines
			    rest-lines
			    port
			    port-name
			    (cons line body)
			    vars)]))]))))))))
  
  (define-struct link (name sig expr links))
  (define-struct sig-explode-pair (sigpart exploded))

  (define parse-compound-unit
    (lambda (expr body)
      (syntax-case body ()
	[((import . imports)
	  (link . links)
	  (export . exports))
	 (and (literal? import) (literal? link) (literal? export))
	 (let* ([imports (parse-imports 'compound-unit/sig #f #t expr (syntax imports))])
	   (let ([link-list (syntax->list (syntax links))])
	     (unless link-list
	       (syntax-error 'compound-unit/sig expr 
			     "improper `link' clause form"
			     (syntax links)))
	     (let* ([bad
		     (lambda (why sub)
		       (syntax-error 'compound-unit/sig expr 
				     (format "bad `link' element~a" why)
				     sub))]
		    [links
		     (map
		      (lambda (line)
			(syntax-case line ()
			  [(tag : sig (expr linkage ...))
			   (literal? :)
			   (begin
			     (unless (identifier? (syntax tag))
			       (bad ": link tag is not an identifier" line))
			     (make-link (syntax-e (syntax tag))
					(get-sig 'compound-unit/sig (syntax expr) #f (syntax sig))
					(syntax expr)
					(syntax->list (syntax (linkage ...)))))]
			  [(tag . x)
			   (not (identifier? (syntax tag)))
			   (bad ": tag is not an identifier" (syntax tag))]
			  [(tag : sig (expr linkage ...) . rest)
			   (literal? :)
			   (bad ": extra expressions in sub-clause" line)]
			  [(tag : sig (expr . rest))
			   (literal? :)
			   (bad ": illegal use of `.' in linkages" line)]
			  [(tag : sig)
			   (literal? :)
			   (bad ": expected a unit expression and its linkages" line)]
			  [(tag : sig . e)
			   (literal? :)
			   (bad ": unit expression and its linkages not parenthesized" line)]
			  [(tag :)
			   (literal? :)
			   (bad ": expected a signature" line)]
			  [(tag)
			   (bad ": expected `:'" line)]
			  [_else
			   (bad "" line)]))
		      link-list)]
		    [in-sigs imports]
		    [find-link
		     (lambda (name links)
		       (let loop ([links links])
			 (cond
			  [(null? links) #f]
			  [(eq? name (link-name (car links)))
			   (car links)]
			  [else (loop (cdr links))])))]
		    [find-sig
		     (lambda (name sigs)
		       (let loop ([sigs sigs])
			 (cond
			  [(null? sigs) #f]
			  [(and (signature? (car sigs))
				(eq? name (signature-name (car sigs))))
			   (car sigs)]
			  [else (loop (cdr sigs))])))]
		    [flatten-path
		     (lambda (clause path var-k unit-k)
		       (letrec ([check-sig
				 (lambda (sig use-sig)
				   (when use-sig
				     (with-handlers ([exn:unit?
						      (lambda (exn)
							(syntax-error 
							 'compound-unit/sig expr
							 (exn-message exn)))])
				       (verify-signature-match
					'compound-unit/sig #f
					(format "signature ~s" (signature-src use-sig))
					(explode-sig use-sig)
					(format "signature ~s" (signature-src sig))
					(explode-sig sig)))))]
				[flatten-subpath
				 (lambda (base last use-sig name sig p)
				   (cond
				    [(stx-null? p) 
				     (check-sig sig use-sig)
				     (unit-k base last name (if use-sig
								use-sig
								sig))]
				    [(or (not (stx-pair? p))
					 (not (identifier? (stx-car p))))
				     (syntax-error 'compound-unit/sig expr
						   path)]
				    [(memq (syntax-e (stx-car p)) (signature-vars sig))
				     (if (and (stx-null? (stx-cdr p)) (not use-sig))
					 (let* ([id-nopath (syntax-e (stx-car p))]
						[id (if name
							(string->symbol 
							 (string-append name
									":"
									(symbol->string id-nopath)))
							id-nopath)])
					   (var-k base id id-nopath))
					 (syntax-error 'compound-unit/sig expr
						       (format 
							"bad `~a' path: \"~a\" is a variable" 
							clause
							(syntax-e (stx-car p)))
						       path))]
				    [(find-sig (syntax-e (stx-car p)) (signature-elems sig))
				     =>
				     (lambda (s)
				       (flatten-subpath base
							(syntax-e (stx-car p))
							use-sig
							(let ([n (symbol->string 
								  (signature-name s))])
							  (if name
							      (string-append name ":" n)
							      n))
							s
							(stx-cdr p)))]
				    [else
				     (syntax-error 'compound-unit/sig expr
						   (format 
						    "bad `~a' path: \"~a\" not found"
						    clause
						    (syntax-e (stx-car p)))
						   path)]))])
			 (let-values ([(p use-sig)
				       (syntax-case path ()
					[_
					 (identifier? path)
					 (values (list path) #f)]
					[(name : sig)
					 (and (identifier? (syntax name))
					      (literal? :))
					 (values (list (syntax name))
						 (get-sig 'compound-unit/sig expr
							  #f
							  (syntax sig)))]
					[((elem ...) : sig)
					 (and (andmap (lambda (s)
							(and (identifier? s)
							     (not (eq? (syntax-e s) ':))))
						      (syntax->list (syntax (elem ...))))
					      (literal? :))
					 (values (syntax (elem ...))
						 (get-sig 'compound-unit/sig expr
							  #f
							  (syntax sig)))]
					[(elem1 elem ...)
					 (andmap (lambda (s)
						   (and (identifier? s)
							(not (eq? (syntax-e s) ':))))
						 (syntax->list (syntax (elem1 elem ...))))
					 (values path #f)]
					[else
					 (syntax-error 'compound-unit/sig expr
						       (format 
							"bad `~a' path"
							clause)
						       path)])])
			   (cond
			    [(find-link (syntax-e (stx-car p)) links)
			     => (lambda (link) 
				  (flatten-subpath (link-name link)
						   (syntax-e (stx-car p))
						   use-sig
						   #f
						   (link-sig link)
						   (stx-cdr p)))]
			    [(find-sig (syntax-e (stx-car p)) in-sigs)
			     => (lambda (sig) 
				  (let ([s (symbol->string (signature-name sig))])
				    (flatten-subpath #f
						     (syntax-e (stx-car p))
						     use-sig
						     s
						     sig
						     (stx-cdr p))))]
			    [else
			     (syntax-error 'compound-unit/sig expr
					   (format 
					    "bad `~a' path: \"~a\" not found"
					    clause
					    (syntax-e (stx-car p)))
					   path)]))))])
	       (check-unique (map link-name links)
			     (lambda (name)
			       (syntax-error 'compound-unit/sig expr
					     (format "duplicate sub-unit tag \"~s\"" name))))
	       (check-unique (map signature-name imports)
			     (lambda (name)
			       (syntax-error 'compound-unit/sig expr
					     (format "duplicate import identifier \"~s\"" name))))
	       (check-unique (append (map signature-name imports)
				     (map link-name links))
			     (lambda (name)
			       (syntax-error 'compound-unit/sig expr
					     (format 
					      "name \"~s\" is both import and sub-unit identifier" 
					      name))))
	       ;; Expand `link' clause using signatures
	       (for-each
		(lambda (link)
		  (set-link-links! 
		   link
		   (map
		    (lambda (link)
		      (flatten-path 'link link
				    (lambda (base var var-nopath)
				      (make-sig-explode-pair
				       var
				       (list
					(if base
					    (list base var)
					    var))))
				    (lambda (base last id sig)
				      (make-sig-explode-pair
				       (rename-signature sig last)
				       (if base
					   (list (cons base (flatten-signature id sig)))
					   (flatten-signature id sig))))))
		    (link-links link))))
		links)
	       (let ([export-list (syntax->list (syntax exports))])
		 (unless export-list
		   (syntax-error 'compound-unit/sig expr 
				 "improper `export' clause form"
				 (syntax exports)))
		 (let* ([upath? (lambda (p)
				  (or (identifier? p)
				      (and (stx-list? p)
					   (andmap identifier? (stx->list p)))))]
			[spath? (lambda (p)
				  (syntax-case p ()
				    [(name : sig)
				     (and (literal? :)
					  (upath? (syntax name))
					  (or (identifier? (syntax sig))
					      (parse-signature 'compound-unit/sig expr #f (syntax sig))))
				     #t]
				    [_else
				     (upath? p)]))]
			[exports 
			 (map
			  (lambda (export)
			    (syntax-case export ()
			      [(open spath)
			       (literal? open)
			       (begin
				 (unless (spath? (syntax spath))
				   (syntax-error 'compound-unit/sig expr 
						 "bad `open' sub-clause of `export'"
						 export))
				 (flatten-path 'export
					       (syntax spath)
					       (lambda (base var var-nopath)
						 (syntax-error 
						  'compound-unit/sig expr 
						  "`open' sub-clause path is a variable"
						  (car export)))
					       (lambda (base last name sig)
						 (if base
						     (make-sig-explode-pair
						      (signature-elems sig)
						      (cons base 
							    (map
							     list
							     (flatten-signature name sig)
							     (flatten-signature #f sig))))
						     (syntax-error 
						      'compound-unit/sig expr 
						      "cannot export imported variables"
						      export)))))]
			      [(var (upath vname) . exname)
			       (literal? var)
			       (let ([upath (syntax upath)]
				     [vname (syntax vname)]
				     [exname (syntax exname)])
				 (unless (and (upath? upath)
					      (identifier? vname)
					      (or (stx-null? exname)
						  (and (stx-pair? exname)
						       (identifier? (stx-car exname))
						       (stx-null? (stx-cdr exname)))))
				   (syntax-error 'compound-unit/sig expr 
						 "bad `var' sub-clause of `export'"
						 export))
				 (flatten-path 'export
					       (if (identifier? upath)
						   (list upath vname)
						   (append (stx->list upath) (list vname)))
					       (lambda (base var var-nopath)
						 (if base
						     (make-sig-explode-pair
						      (list (if (stx-null? exname)
								var-nopath
								(syntax-e (stx-car exname))))
						      (list base
							    (if (stx-null? exname)
								(list var var-nopath)
								(list var (syntax-e (stx-car exname))))))
						     (syntax-error 
						      'compound-unit/sig expr 
						      "cannot export imported variables"
						      export)))
					       (lambda (base last name var)
						 (syntax-error 
						  'compound-unit/sig expr 
						  "`var' sub-clause path specifies a unit"
						  export))))]
			      [(unit spath . exname)
			       (literal? unit)
			       (let ([spath (syntax spath)]
				     [exname (syntax exname)])
				 (unless (and (spath? spath)
					      (or (stx-null? exname)
						  (and (stx-pair? exname)
						       (identifier? (stx-car exname))
						       (stx-null? (stx-cdr exname)))))
				   (syntax-error 'compound-unit/sig expr 
						 "bad `unit' sub-clause of `export'"
						 export))
				 (flatten-path 'export
					       spath
					       (lambda (base var var-nopath)
						 (syntax-error 
						  'compound-unit/sig expr 
						  "`unit' sub-clause path is a variable"
						  export))
					       (lambda (base last name sig)
						 (if base
						     (make-sig-explode-pair
						      (list (rename-signature
							     sig
							     (if (stx-null? exname)
								 last
								 (syntax-e (stx-car exname)))))
						      (let ([flat (flatten-signature name sig)])
							(cons base 
							      (map
							       list
							       flat
							       (flatten-signature 
								(symbol->string
								 (if (stx-null? exname)
								     last
								     (syntax-e (stx-car exname))))
								sig)))))
						     (syntax-error 
						      'compound-unit/sig expr 
						      "cannot export imported variables"
						      export)))))]
			      [_else
			       (syntax-error 'compound-unit/sig expr 
					     (format 
					      "bad `export' sub-clause")
					     export)]))
			  export-list)])
		   (check-unique (map
				  (lambda (s)
				    (if (signature? s)
					(signature-name s)
					s))
				  (apply
				   append
				   (map sig-explode-pair-sigpart exports)))
				 (lambda (name)
				   (syntax-error 'compound-unit/sig expr
						 "name is exported twice"
						 name)))
		   (values (map link-name links)
			   (map link-expr links)
			   (map (lambda (link) (explode-sig (link-sig link))) links)
			   (map
			    (lambda (link)
			      (map (lambda (sep)
				     (explode-named-sig (sig-explode-pair-sigpart sep)))
				   (link-links link)))
			    links)
			   (flatten-signatures imports)
			   (map (lambda (link)
				  (apply
				   append
				   (map 
				    sig-explode-pair-exploded 
				    (link-links link))))
				links)
			   (map sig-explode-pair-exploded exports)
			   (explode-named-sigs imports)
			   (explode-sig
			    (make-signature
			     'dummy
			     'dummy
			     (apply
			      append
			      (map sig-explode-pair-sigpart exports))))))))))]
	[_else (raise-syntax-error 
		'compound-unit/sig
		"bad syntax"
		expr)])))
  
  (define parse-invoke-vars
    (lambda (who rest expr)
      (parse-imports who #t #f expr rest)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (export parse-unit
	  parse-compound-unit
	  parse-invoke-vars

	  parse-unit-renames
	  parse-unit-imports
	  parse-unit-body

	  signature-vars
	  do-rename
	  get-sig
	  explode-sig
	  explode-named-sigs
	  check-signature-unit-body
	  flatten-signatures))