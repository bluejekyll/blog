+++
title = "Rust from a Java dev"
date = 2015-05-14
aliases = ["/java/rust/2015/05/14/rust-from-a-java-dev.html"]
+++

# A little background

Let me say first off, I am not one of those developers that jumps on the next cool language. I have a very specific reason why I am interested in Rust. Rust represents an evolution of systems languages of which our options have been limited now for decades. A systems language in my opinion, and I'm sure there is lots of disagreement about this, but the traits important to me are:

- Constant and predictable runtime
- Direct access to OS primitives and interfaces
- Low overhead for the language runtime

[Wikipedia defines](http://en.wikipedia.org/wiki/System_programming_language) it this way:

```
System software is computer software designed to operate and control
 the computer hardware, and to provide a platform for running application
 software. System software includes software categories such as operating
 systems, utility software, device drivers, compilers, and linkers.
```

That definition seems weak to me, but the line between systems and application languages had been blurred long ago. When choosing a language for any project, there should be specific criteria by which you determine what you need based on what you need to accomplish. Most languages will allow you to accomplish any task you want, but they offer features that may make what you want to do either easier or harder. Picking the right language is important, how many external libraries are available to support what you're building, how many developers exist to support you if you need to hire/contract work, how many unknown bugs or issues remain undiscovered in the language. For most of my use cases Java has always been the right language, but this post isn't about Java, it's about Rust. Also, I don't want to get into defense of Java/JVM over other languages like Go, Ruby, Scala, Clojure, etc. I've been developing in Java since 1997, and I stopped using C/C++ for anything major after 2002.

I discovered Rust while exploring Go. This was only a few months ago, which make me a late-comer to this game. Remember the two bullet points above; constant and predictable runtime, direct access to OS primitives. Go has always confused me, is it a systems language? It's got a Garbage Collector (GC means unpredictable runtime) and it's awkward access to C structures means that it can not easily interface with the OS. It was the latter issue that brought me to Rust which allows for direct access to C structures through it's FFI (Foreign Function Interface). For you Java devs who've always hated working with JNI this is a godsend (Yes, JNA made it easier and Panama should help immensely). Go ends up being better at potentially replacing Java and the JVM.

# On to Rust

What makes Rust unique in this landscape is that it's a new language with no GC, but it at the same time it handles the memory management for you. It allows for the same direct access to C as C++ does, with no significant hurdles. Coming from a Java landscape where there are a multitudes of libraries in addition to the massive JDK standard library, what this means is you have access to not just Rust elements, but also the massive C library out there. I think of Rust as having two core features, memory safety and management. But by no means is this the limit to what Rust provides. As a Java developer not having to worry about memory allocation and deallocation is nice. I've gotten quite used to a GC which makes sure that I don't have to worry about seg faults and memory leaks any more (yes, people create memory leaks in Java too, but you have to make some very poor choices for that).

# Option\<T\>

Rust is trying to position it self as a replacement for C, and I've become convinced that unlike C++ and some other languages out there, it actually can. This is because of the fact that Rust gives you access to all the pointer primitives you have in C, but guarantees that accessing the data behind those pointers is always valid. One cool thing that I really like about Rust is that it does not allow for null, this was a little mind blowing, though after building a small project in Swift I learned how nice it is to know that the data you're accessing is either there or not.

Option is a primitive in Rust that is used to return or pass around data which is optionally there or not. It's an enum (union) type in Rust. When in Java we gave up segmentation faults, what we replaced them with were NullPointerExceptions, the only advancement that gives us in the end is the stacktrace. Rust simply says, this data may or may not exist behind the Option type. This tells the developer immediately that you need to handle those two cases. It also gives you some handy functions at your disposal to handle the null case elegantly:

```rust
fn unwrap_or(self, def: T) -> T;
```

Which returns the value T if there is nothing, i.e. the Option is None. In Java 1.8 there is now the Optional type which acts the same way. I for one am going to start using this in all my future Java code as this is a very nice feature. Scala has had this from it's foundations as well.

# Enums in Rust are cool

Enumerations in Rust are cool, they are a union type. There's not a great corollary to this in Java. The first thing to understand is that an enum in Rust allows you to define values that are stored with the enum, this is done very efficiently in the compiled code, but I won't get into that.

Look at the Option enum:

```rust
pub enum Option<T> {
    None,
    Some(T),
}
```

The first thing you'll notice as a Java dev, is that enums can be Genericized. I've wanted this so many times in Java and end up doing funky stuff to work around it. Now when using this you need to do something that was unfamiliar to me, [destructuring](http://doc.rust-lang.org/1.0.0-beta.4/book/patterns.html), the `unwrap()` function looks like this:

```rust
fn unwrap(self) -> T {
    if let Some(v) = self {
        return v;
    }
    panic!("This is None, can't unwrap()");
}
```

`v` is a locally scoped variable defined to unwrap the enum where the enum is of type Some. This type destructuring is neat and allows for very flexible usage of enums in Rust. Ok, this introduces panic! which is essentially similar to throwing a RuntimeError in Java (the `!` says that this is a [macro](http://doc.rust-lang.org/1.0.0-beta.4/book/macros.html)). This introduces an issue I have with the language, no exceptions (well, except for panic!). Basically, Rust allows you to throw one type of Exception, and comparing it to Errors in Java is good. Errors should not be caught in Java, they are non-recoverable. Panic is similar, and similarly should almost never be used. But they are there, and at Rust deals the the stack unwinding properly so we don't need to worry about dangling pointer issues. I'm torn as to what I'd prefer to see, and this article is a great writeup on the issue.

# Errors in Rust are a little juvenile, but still really neat

So this is where you can see the roots of the desire for Rust to be a bit like C. In C there are no Exceptions, there are return codes. What makes Rust's errors better than C is that since they are enums, there is no question to if the result is good or bad. Objects are generally passed in by reference and then the data returned through that referred parameter. Rust is similar, but instead uses an enum for the result:

```rust
enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

Where there might be an error you return Result. I actually like this, I've noticed you're code becomes much more condensed than the try{} finally {} blocks in Java, though the AutoCloseable stuff has made that nicer. There is no finally, it seems that there has been a long debate in the Rust community about this. If you need finalization, then you need to implement the trait Drop for your struct.

The reason I say errors are juvenile in Rust is that it becomes hard to write functions which join different error types and return those errors. In Java it's easy to wrap any Exception and pass that up the call stack as a cause of the Exception. In Rust this still feels very awkward. In Rust you can't extend objects, all structs are final. What this means is that if you want to create a new Error type in rust, you need to write a bunch of code, or maybe I'm doing it wrong. I imagine this will get better over the coming releases.

# Ownership and Lifetimes

This is where Rust get's a little difficult. For Java devs it's important to think about the lifetime of objects because your always concerned with how complex the Garbage Collector will have to work, or not make dumb mistakes that lead to memory leaks. Ownership is something that you have to be concerned with when working with Threads in Java. It's also something to make sure where you don't have any dangling references. In Rust it's not just something you need to be cognizant of, you have to abide by it's strict rules related to these two concepts.

Rust introduced me to a concept of tracking Lifetimes. Initially reading the docs and specs, I thought this was going to be the hard thing to wrap my head around, but in the end it's the Ownership rules that I find to be the difficult piece. See this [question I posted](http://stackoverflow.com/questions/29818290/how-to-convert-an-iterator-on-a-tuple-of-string-string-to-an-iterator-of-st) in Stack Overflow to get a bit of an understanding to the complexities of Ownership rules.

# LLVM

Rust compiles to the LLVM byte code. The LLVM is a really awesome concept and reality. I've been following it since Apple decided to start using it in their OS, and it's clear to mean that this is itself a game changer. The concept behind the LLVM is basically to produce architecture agnostic intermediate code which is then compiled to for the specific architecture on which the code needs to run. This is powerful because it allows for all high level languages only worry about parsing, but the machine code generation is only written once for each architecture. The GCC started doing something similar a while back, but the LLVM has, IMO, done a better job.

As an example, asm.js is a new JavaScript spec that defines a subset of JS which can be optimized by the interpreter to be run like machine code. As a consequence there is no need to do Garbage Collection and some of the numbers I've seen show asm.js applications running at 50% native speeds. But, it comes at a cost, asm.js is complex, writing it by hand is difficult, but this is where the LLVM shines, the [Emscripten](https://kripken.github.io/emscripten-site/index.html) tool is a compiler for translating C and C++ into asm.js. What this means is that for us people who like strongly typed languages, we will be able to use them instead of JS to wrote for the Web, which is really awesome. By extension, this means that Rust too could be used for writing web code.

# When should you start using Rust?

Now, depending on what you need it for. For me, having a predictable runtime (no GC) is important to a project I'm working on. Having that also run at native C like speed is also desirable. If you have a project that also needs this, Rust seems like the perfect fit. If on the other hand you have a high application to build and time critical deadlines to get it into production I'd still stick with Java or Scala to deliver that. Rust doesn't have the same amount of libraries and hasn't been beaten around in production to discover all it's bugs yet. It's also possible that the language will change a bit over time, but this will probably all calm down after the 1.0 release.
