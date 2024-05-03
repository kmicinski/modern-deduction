## Modern Deduction Blog 0: Introduction

Over the past several years, my collaborators and I have been exploring
the design of high-performance logic programming engines for a wide
variety of tasks, including program analysis (points-to analysis,
abstract interpretation), graph analytics (transitive closure,
PageRank), and security (binary code similarity, disassembly, and
decompilation). We (myself, my collaborators, and our students) have
engineered a variety of systems aiming for both (a) state-of-the-art
performance at the highest scale (shared-memory parallelism,
distribution via MPI, SIMD on GPUs, and GPU cluster computing) and (b)
semantic extensions (monotonic aggregation, algebraic data) to
Datalog.

I will be chronicling our efforts (mostly the relevant background) in
this series of posts, Modern Deduction. While we worked on this project 
for several years, we recently recieved an [NSF PPoSS Large](https://thomas.gilray.org/news/pposs.html)
which will fund our efforts for the next several years. I will plan to put 
out a post once every month or two.
