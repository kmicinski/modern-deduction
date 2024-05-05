---
layout: post
title:  "Modern Deduction Post 1: Chain-Forward Computation"
date:   2024-04-05
permalink: /modern-deduction/1
---

Our setting is logic programming, a field which attempts to design
programming languages whose semantics have a close relationship to
formal logic. The reason we might want to do this is that it suits our
application domain more precisely than an implementation in a
traditional programming language. Thus, using a logic programming
language allows us to write more obviously-correct code, and perhaps
even code that can be extracted cleanly from a certified
implementation. Alternatively, if we did it ourselves, we'd have to do
what our compiler (interpreter, ...) would do anyway, so there's no
sense in doing it manually. Unfortunately, when we see a powerful
tool, we are tempted to use it for everything: if our application is
not ultimately-suited to the operationalization strategy of the logic
programming engine we're using, we simply obfuscate the issue in a
veneer of formalism and end up with leaky abstractions. This is, I
speculate, why logic programming languages have never caught on
broadly for general-purpose programming. In this blog, I will detail
the various trade-offs and implementation paradigms for modern logic
programming engines, starting from Datalog and with a focus on program
analysis.

The history of logic is rich, and I will not attempt to recount it
all. Here I will focus on more restricted, application-specific
languages, especially Datalog and its derivatives. The specific
features of these languages, and the particulars of their
implementation, often dovetail with a "right place, right time"
effect. For example, [Datalog backed by
BDDs](https://suif.stanford.edu/papers/pldi04.pdf) was a significant
step forward in terms of production program analyses. More modern
implementations eschew BDDs for more explicit representations, but it
remains the case that engineers and computer scientists are on the
lookout for logic-programming-based approaches to hard problems,
especially those which deal intrinsically in the enumeration of large
state spaces.

Perhaps one of logic programming's most exciting motivations is
program analysis. Program analysis systems automatically prove
properties about, find bugs in, or simply help us understand our
programs. These can come in a variety of forms from on-demand
in-editor type-checking to whole-program (runs in microseconds),
context-sensitive points-to analysis (days). Program analyses are
notoriously hard to specify, and are especially hard to implement in a
way that provides a close relationship to the formal
specification. Additionally, program analyses often grapple with large
state spaces in practice to solve interesting problems, and require
some amount of thought regarding high-performance implementation.

#### Chain-Forward Computation and Datalog

The central evaluation mechanism in Datalog, and its derivatives, is
to saturate a set of rules (e.g., Horn clauses) to a fixed point, to
obtain a knowledge database in some domain. We call the computation
"chain forward" because the evaluation of such languages is guided by
an ordering on knowledge, typically set inclusion (in the case of
traditional Datalogs). In these settings, we define an "immediate
consequence" operator, which tells us everything which must be known,
as a consequence of what we currently know; crucially, this operator
is typically monotonic: we do not lose knowledge over time, though we
will discuss some interesting departures from this
assumption. Applying this immediate consequence operator repeatedly
yields a stream of knowledge databases over time. Assuming the
immediate consequence operator is monotone, this stream of knowledge
databases over time forms an ascending chain according to the ordering
on knowledge.

Datalog's syntax consisting of "facts" and "rules." Facts are "known
statements" and always have the following form: `R(c0, ...)`, where
`R` is a relation name (identifier) and the arguments are
constants. For example `>(3,2)` might be a fact, along with
`reaches("n0","n1")`. But facts may not include variables, for
example: `reaches("n0",x)` is disallowable as a fact, because `x` is
not bounded in any way.

Let's look at simplest interesting example: transitive closure. The
Datalog program (technically in Soufflé here) to implement transitive
closure [example (`tc.dl`)]() is here (I elide some declarations):

```
// ...
edge(1,2). edge(2,3). edge(3,5). edge(5,4). edge(4,1). edge(4,8).
path(x, y) :- edge(x, y).
path(x, y) :- path(x, z), edge(z, y).
```

Running this program in Soufflé gives us an output database in the
file `path.csv.`

#### Datalog can't search (disjunction), saturated conjunctions only

Disjunctions in the head of a rule is disallowed, as it is not
semantically within reach of Datalog. The following is invalid:

```
Q(x,...) ∨ R(x,...) ← P(...) ∧ R(...)
```

Once we have more than one positive literal in a clause, we need a SAT
solver. SAT solvers combine search ("guess new things") and deduction
("derive consequences"); Datalog solvers only employ deduction. Both
SAT and Datalog engines share some overlapping ideas; for example,
both use indexing, to accelerate joins (Datalog) and for efficient
unit propagation (SAT). But (>2)-SAT is strictly harder than Datalog:
2-SAT can be written as Horn clauses (`Q ← R` is `¬R ∨ Q`), but 3-SAT
and beyond are out of reach. By contrast, `∧` in the head of a rule
presents no serious semantic issue: `Q(x,...) ∧ R(x,...) ← ...` can
easily be desugared into two rules: `Q(x,...) ← ...` and `R(x,...) ←
...`.

The degenerate nature of Horn clauses means that it's possible to
define Datalog's evaluation via forward chaining, i.e., modus
ponens. Formalizations of Datalog's semantics is often defined via a
least fixed-points on the lattice given by powersets of tuples,
building up databases (sets of relations) by iterating an "immediate
consequence" operator; relations are sets of ground tuples: `R(1,2)`
but not `R(x,3)`. The semantics grows these relations monotonically
over time by repeated application of modus ponens, extending relations
with (possibly) additional tuples. The process necessarily terminates
as there is a maximimum bound on the number of tuples (generalizing
the case of a fully-connected graph), and the fixed point theorems
tell us that because our domain is finite, we are necessarily destined
to terminate our enumeration.

#### Semi-Naïve Evaluation

One issue with the repeated application of the rules is that if we use
an explicit set-based representation of tuples, each iteration we'll
"rediscover" all knowledge from every previous iteration---this
translates to additional data load, without commensurate knowledge
throughput. In Datalog, the solution is to employ a compilation into
an incrementalized IR, ala semi-naïve evaluation. For example, the
recursive rule in transitive closure becomes:

```
path(x,z) ← path(x,y) ∧ edge(y,z)
          | 
   becomes| No Δ versions for edge as it is static
          |
Δpath(x,z) ← (Δpath(x,y) ∧ edge(y,z)) - path
i.e., 
Δpath(x,z) ∪= (Δpath(x,y) ⋈ edge(y,z)) - path
```

The rule expands into a single rule, because the relation `edge` never
changes--thus, tracking a delta version would be
irrelevant. Additionally, we assume that at the end of each iteration,
`Δpath` is merged into `path`. In the more general case such as:

```
g(y,x) ∧ p(x,z) ← p(x,y) ∧ g(y,z)
```

We would need to split the rule into several versions: one to join
`Δp` with `g`, one to join `p` with `Δg`, and one to join `Δp` with
`Δg`. Think about what would happen if we have only `Δp ⋈ Δg`: if we
have facts `(x,y)` in `Δp` and `(y,z)` in `Δg`, everything works
fine. But what happens if `(x,y)` skips an iteration? It would be hard
to ensure that doesn't happen (though some work certainly explores
this to a degree), and so we diversify our rules to enable us to catch
things in `Δp` and `Δg`.

Previously, I mentioned the resulting rule would look something like:

```
Δpath(x,z) ∪= (Δpath(x,y) ⋈ edge(y,z)) - path
```

In fact, all rules within a fixedpoint (more specifically, an SCC of
rules) will have the structure:

```
ΔR(x...) ∪= (ΔR(x,...) ⋈ Q(y,...)) - R
```

There is a crucial tacit point to be explained here: deduplication,
i.e., `- R` is dirt cheap when implemented thoughtfully, and it is
possible to parallelize nicely. There is no explicit scan of `R` in
implementing subtraction, rather every rule generates a set of
possibly-new tuples, which are deduplicated in some efficient manner
to add to `ΔR` at the end of each iteration, before emptying `ΔR` in
preparation for the next iteration.

#### Relational Algebra 

The explicit focus on bound variables has made the above presentation
informal, as substitution was never defined. Indeed, substitution is
"where computation happens" here in much the same way as in the
λ-calculus. However, handling binders is a bit tedious, and it turns
out there is a better, more systematic way. In the same way that
category theory will avoid mentioning concrete points for products A ×
B, relational algebra will avoid mentioning explicitly-named points. 

Our group's engines are based on compilation to iterated relational
algbera, saturating monotonic deduction to a fixed-point. Relational
algebra (and its extensions) are a nice representation, and I believe
an under-emphasized point is that this is due to the lack of explicit
binding structure--this allows us to write a definitional interpreter
for a conjunctive query in a way which greatly simplifies the
implementation by never have to mention names or perform any
substitution. The computationally "dense" portion of the work is `⋈`,
k-ary joins are typically implemented pipelined into either series or
trees of binary joins. This intuitively makes sense, as `⋈` can be
seen as filtering a cartesian product.
