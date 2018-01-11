---
layout: post
title:  "Branchless #Rust2018"
date:   2018-01-10 00:00:00 -0700
categories: rust
---

*About an oportunity for Rust, as part of the #Rust2018 request*

Recently there were two new issues discovered with CPUs, Meltdown (Intel) and Spectre (all "fast" CPUs?). Both of which basically exploit speculative branch prediction to gain access to memory via what's known as a side-channel attack. There was a Webkit [response](https://webkit.org/blog/8048/what-spectre-and-meltdown-mean-for-webkit/) to this in which they mention they will start utilizing "Branchless Security Checks". A [request](https://blog.rust-lang.org/2018/01/03/new-years-rust-a-call-for-community-blogposts.html) was put out for the Rust community's aspirations of the language in 2018, this post is in that spirit. For me, I would love to see the language continue its explosive growth. Branchless code is potentially an accelerant toward that end.

# The Branchless Opportunity

In Rust it is possible to use generics as a means to write branchless code. It's not the only language that can do this, any language with monomorphization (C++) is capable of this. Here's an [example](https://github.com/bluejekyll/trust-dns/blob/fb9e5cde20902b24462cdb234cbcd4113c89b081/proto/src/rr/domain.rs#L549) of code from the domain `Name` type in TRust-DNS that I've recently rewritten to be branchless:

```rust
    pub fn cmp_with_case(&self, other: &Self, ignore_case: bool) -> Ordering {
        if self.labels.is_empty() && other.labels.is_empty() {
            return Ordering::Equal;
        }

        // we reverse the iters so that we are comparing from the root/domain to the local...
        let self_labels = self.labels.iter().rev();
        let other_labels = other.labels.iter().rev();

        for (l, r) in self_labels.zip(other_labels) {
///             | | | |
/// LOOK HERE  | | | | The branch we'll remove
///           V V V V
            if ignore_case {
                match (*l).to_lowercase().cmp(&(*r).to_lowercase()) {
                    o @ Ordering::Less | o @ Ordering::Greater => return o,
                    Ordering::Equal => continue,
                }
            } else {
                match l.cmp(r) {
                    o @ Ordering::Less | o @ Ordering::Greater => return o,
                    Ordering::Equal => continue,
                }
            }
        }

        self.labels.len().cmp(&other.labels.len())
    }
```

This is the new code is now split across two objects, [`Name`](https://github.com/bluejekyll/trust-dns/blob/95e35576f7a1d4cf754750538ddf33838c6f4d42/proto/src/rr/domain/name.rs#L550) and [`Label`](https://github.com/bluejekyll/trust-dns/blob/95e35576f7a1d4cf754750538ddf33838c6f4d42/proto/src/rr/domain/label.rs#L113). It now uses a generic to perform the comparison:

```rust
/// From Name
    pub fn cmp_with_f<F: LabelCmp>(&self, other: &Self) -> Ordering {
        if self.labels.is_empty() && other.labels.is_empty() {
            return Ordering::Equal;
        }

        // we reverse the iters so that we are comparing from the root/domain to the local...
        let self_labels = self.labels.iter().rev();
        let other_labels = other.labels.iter().rev();

        for (l, r) in self_labels.zip(other_labels) {
///             | | | |
/// LOOK HERE  | | | | No branch the <F> is a type parameter instead
///           V V V V
            match l.cmp_with_f::<F>(r) {
                Ordering::Equal => continue,
                not_eq => return not_eq,
            }
        }

        self.labels.len().cmp(&other.labels.len())
    }


/// From Label, this is the is where the type comes into play
    pub fn cmp_with_f<F: LabelCmp>(&self, other: &Self) -> Ordering {
        let s = self.0.iter();
        let o = other.0.iter();

        for (s, o) in s.zip(o) {
///             | | | |
/// LOOK HERE  | | | | No branch for the comparison (the match is for the result of the comparison)
///           V V V V
            match F::cmp_u8(*s, *o) {
                Ordering::Equal => continue,
                not_eq => return not_eq,
            }
        }

        self.0.len().cmp(&other.0.len())
    }

/// And here are the comparison types:

/// Label comparison trait for case sensitive or insensitive comparisons
pub trait LabelCmp {
    /// this should mimic the cmp method from [`PartialOrd`]
    fn cmp_u8(l: u8, r: u8) -> Ordering;
}

/// For case sensitive comparisons
pub struct CaseSensitive;

impl LabelCmp for CaseSensitive {
    fn cmp_u8(l: u8, r: u8) -> Ordering {
        l.cmp(&r)
    }
}

/// For case insensitive comparisons
pub struct CaseInsensitive;

impl LabelCmp for CaseInsensitive {
    fn cmp_u8(l: u8, r: u8) -> Ordering {
        l.to_ascii_lowercase().cmp(&r.to_ascii_lowercase())
    }
}
```

To make calling these easier I have two standard methods defined:

```rust
    /// Case sensitive comparison
    pub fn cmp_case(&self, other: &Self) -> Ordering {
        self.cmp_with_f::<CaseSensitive>(other)
    }

    /// Case insensitive comparison
    fn cmp(&self, other: &Self) -> Ordering {
        self.cmp_with_f::<CaseInsensitive>(other)
    }
```

I did this to reduce errors around passing the wrong boolean parameter to the compare function. The point is that this is branchless. Here's another recent post from @RReverser, ["Conditional enum variants in Rust"](https://rreverser.com/conditional-enum-variants-in-rust/), while not explicitly about branchless programming, it's a similar usage of type parameters as a means improve the code.

# Things could be better

If [const generics](https://github.com/rust-lang/rfcs/blob/master/text/2000-const-generics.md) are implemented, I think we could change the case comparison logic to this:

```rust
    pub fn cmp_with<const CASE: bool>(&self, other: &Self) -> Ordering {
        let s = self.0.iter();
        let o = other.0.iter();

        for (s, o) in s.zip(o) {
///             | | | |
/// LOOK HERE  | | | | This branch will be optimized out by the compiler b/c it's a const bool
///           V V V V
            let (s, o) = if CASE {
                (s, o)
            } else {
                (s.to_lowercase(), o.to_lowercase())
            };

            match s::cmp(o) {
                Ordering::Equal => continue,
                not_eq => return not_eq,
            }
        }

        self.0.len().cmp(&other.0.len())
    }
```

This requires that the compiler optimizes out the constant boolean dictated through the const generic. It's less code than the technique I used before, though possibly not as obvious that it's branchless. That's of course due to the fact that it's the compiler that would optimize out the branch for the case comparison. This of course is not necessary for branchless programming in Rust, but it might be more approachable.

# Excuse me, Ben

*I just wanted to point out that your code is not actually branchless*, you're currently thinking, and you're right! All those match statements and the for loops are branches. Of which I am aware, but if you go back and read the Webkit [article](https://webkit.org/blog/8048/what-spectre-and-meltdown-mean-for-webkit/), perhaps you can see where type parameters could be used to make that style of programming easier.

Thanks!