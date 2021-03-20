+++
title = "Did Rust make Trust-DNS any safer?"
date = 2021-01-23
description = "Five years of bugs in Trust-DNS, looking back at issues"
draft = true

[taxonomies]
topics=["rust"]
+++

Trust-DNS started out as an attempt to build *something* meaningful in Rust. It touched a few sweet spots for me, areas in programming that I don't often get to explore, but have always enjoyed. DNS operates in this space, something that needs to be high-performance, have low memory foot print, and interesting network code. I thought it would be interesting to go back over the 268 issues closed over that period and see if there is anything we can learn about common issues in the project, as well as what types of bugs were common to experience during that development. For example, can we determine if Rust was a help in building this software? Did the language hold true to it's promise of building more reliable software with fewer issues occurring from programming mistakes other languages more easily allow?

## Method

I was collecting all of this data in a spreadsheet, but it quickly became apparent that because my Google-sheets-fu is not great, this was super limiting. So I took this opportunity to learn something else, [Jupyter Notebooks](https://jupyter.org). I won't write a lot about that here, but let's say that experience has taught me to that there are better ways to collect data and present it while your working on it, rather than just doing things on the CLI and putting that into a spreadsheet. For example, this review has three different data-sources: Git, Github, and a self-reviewed CSV of all the bugs in the project. I chose to use the [evcxr](https://github.com/google/evcxr/blob/master/evcxr_jupyter/README.md) Jupyter kernel, which overall is a great experience (yes, I am a huge Rust fan and choose to use that for anything and everything when possible). For much of the data analysis, the [serde](https://docs.rs/serde/1.0.123/serde/) serialization and deserialization library was enough to derive types, especially from the Github API and the CSV file–the Git repo was queried directly with the [git2](https://docs.rs/git2/0.13.17/git2/) crate. For all the drawings, the [plotters](https://docs.rs/plotters/0.3.0/plotters/) crate was used, with the `evcxr` feature enabled. What's this offers such a great experience for extracting and visualizing data, I can easily see why it's so popular for folks working in the data sciences. I am sure others are far more capable with this drawing library, but it was enough for my needs.

With the exception of the [trust-dns](https://github.com/bluejekyll/trust-dns), all the data used in this post was posted with this article: the [github issues](all-issues.json) as of 2021-2-17 (TODO: update all data before publishing), the categorized and [reviewed bugs](reviewed-bugs.tsv), and finally the [notebook](issues_workbook.ipynb) for producing graphs. Bugs were also classified by [Common Weakness Enumeration](https://cwe.mitre.org/data/definitions/1350.html).

## Questions attempted to answer

One thing to note is that this project (as of this writing) has no `unsafe` code blocks. We've managed to maintain this as a requirement since the founding of the project. And one thing we don't see in the reviewed issues are issues common in C and C++, such as use-after-free, uninitialized memory, dereferencing issues, etc. But that's not to say there are no bugs. That would be ridiculous, I've yet to work with any language that prevents bugs, mostly because humans rarely can account for all logic before writing code. The better questions are more around do we see a correlation of bugs to any of the activities in maintaining a software project.

Here are the questions I thought would be interesting to ask:

- Is there a correlation between number of changes in a release to reported bugs?
- What about when there are new contributors to the project?
- How about when the project sees increased usage?

## TBD, add sections and graphs


## Rust holds up to high expectations

It's hard to quantify how issues actually translate to user experience with a language. For example, I know that Rust is remains challenging for new users. In my experience though, the number of issues that come into this project is manageable by myself and [@djc](https://github.com/djc), basically requiring less than an hour a week to keep up with changes and bugs. Bugs are rarely reported, such that I just don't see them as a primary concern for the project, we have maintained varying degrees of 80-90% test coverage which keeps our confidence high on submitted patches not causing errors. That said, the project can be vastly improved, feedback I received recently was, "Trust-DNS is really hard." And that doesn't need to be true, so I hope we can start reducing it's complexity and make it easier for new users. While we have things to improve, the choice of Rust has been a great one–bug prevention has been shifted far to the left with compile time detection resulting in fewer test failures and missed issues making it into releases.
