+++
title = "Did Rust make Trust-DNS any safer?"
date = 2021-01-23
description = "Five years of bugs in Trust-DNS, looking back at issues"

[taxonomies]
topics=["rust"]
+++

Trust-DNS started out as an attempt to build something meaningful in Rust. It touched a few sweet spots for me, areas in programming that I don't often get to explore, but have always enjoyed. DNS operates in this space, something that needs to be high-performance, have low memory foot print, and interesting network code. I thought it would be interesting to go back over the 268 issues closed over that period and see if there is anything we can learn about common issues in the project, as well as what types of bugs were common to experience during that development. For example, can we determine if Rust was a help in building this software? Did the language hold true to it's promise of building more reliable software with fewer issues occurring from programming mistakes other languages more easily allow?

