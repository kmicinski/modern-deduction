;; Relational algebra
#lang racket

(define relation? symbol?)
(define atom? symbol?) ;; atomic lits are symbols
;; variables must be explicitly tagged, not 'x, but '(var x)
(define (var? x) (match x [`(var ,(? symbol? x)) #t] [_ #f]))
(define (var-or-atom? x) (or (atom? x) (var? x)))
(define (fact? f)
  (match f
    [`((,(? relation? r) ,(? atom?) ...)) #t]
    [_ #f]))
(define (rule? r)
  (match r
    [`((,(? relation? head-rel) ,(? var-or-atom?) ...) <-- 
       (,(? relation? body-rels) ,(? var-or-atom?) ...) ...)
     #t]
    [_ #f]))

;; should all be true
(rule? '((p) <--))
(rule? '((r) <-- (q)))
(rule? '((path x y) <-- (edge x x)))
(rule? '((path x y) <-- (edge x y) (path y z)))

(define (query? q)
  (match q
    ;; scan a relation
    [`(scan ,(? relation? R)) #t]
    [`(select from ,(? relation? R)
              where column ,(? nonnegative-integer? n)
              equals ,(? atom?))
     #t]
    ;; natural join on the first N columns, values must be equal
    [`(,(? query? q0) ⋈ ,(? query? q1) on first ,(? nonnegative-integer? N)) #t]
    [`(,(? query? q0) ∪ ,(? query? q0)) #t]
    [`(,(? query? q0) ∩ ,(? query? q0)) #t]
    ;; reorder tuples
    [`(reorder ,(? query? q) ,(? nonnegative-integer?) ...) #t]
    ;; project the first n elements of tuples
    [`(project ,(? query? q) ,(? nonnegative-integer? n)) #t]
    ;; need closed-world assumption
    [`(- ,(? query? q)) #t]
    [_ #f]))

;; q: query?
;; db: hashmap from relation name ↦ ℘(Tuple)
;; universe: ℘(Tuple)
(define (interpret-query q db universe)
  (match q
    [`(scan ,R) (hash-ref db R)]
    [`(select from ,R where ,n equals ,k)
     (filter (lambda (x) (equal? (list-ref x n) k))
             (hash-ref db R))]
    [`(,q0 ∪ ,q1) (set-union (interpret-query q0 db universe) (interpret-query q1 db universe))]
    [`(,q0 ∩ ,q1) (set-intersect (interpret-query q0 db universe) (interpret-query q1 db universe))]
    [`(,q0 ⋈ ,q1 on first ,N)
     (list->set
      (foldl
       (λ (t0 tups)
         (foldl (λ (t1 tups)
                  (if (equal? (take t0 N) (take t1 N))
                      (set-add tups (append (take t0 N) (drop t0 N) (drop t1 N)))
                      tups))
                tups
                (set->list (interpret-query q1 db universe))))
       (set)
       (set->list (interpret-query q0 db universe))))]
    [`(reorder ,q ,order ...)
     (let ([ts (set->list (interpret-query q db universe))])
       (set->list
        (map (λ (t) (map (λ (i) (list-ref t i)) order))
             ts)))]
    [`(project ,(? query? q) ,(? nonnegative-integer? n))
     (list->set (map (λ (t) (take t n)) (set->list (interpret-query q db universe))))]
    ;; need closed-world assumption
    [`(- ,(? query? q))
     (set-subtract universe (interpret-query q db universe))]))

;; relations: hash from relation names to their associated arities
;; herbrand-base is a list of atoms 
(define (herbrand-universe relations herbrand-base)
  (foldl
   (λ (R db)
     (hash-set db
               R 
               (set->list
                (foldl
                 (λ (i lists)
                   (map (lambda (list) (map (lambda (i) (cons i list)) herbrand-base))
                        lists))
                 '(())
                 (range (hash-ref relations R))))))
   (hash)
   (hash-keys relations)))

(herbrand-universe (hash 'R 2 'K 1 'Q 3) '(a b c d e))

(interpret-query '(- ((scan R) ⋈ (scan K) on first 1)) 
                 (hash 'K (list->set '((1 2) (3 4)))
                       'R (list->set '((1 2) (2 3) (3 4) (2 5) (3 1)))))



