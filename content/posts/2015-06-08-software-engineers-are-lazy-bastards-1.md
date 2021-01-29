+++
title = "Software Engineers are lazy bastards, pt. 1"
date = 2015-06-08
description = "I decided to make this a three part piece. This one is about components and modularization, the next about testing, and then I will have a final one on development and operations."
aliases = ["/dev/software/programming/testing/2015/06/08/software-engineers-are-lazy-bastards-1.html"]

[taxonomies]
topics=["programming"]
+++

Not too long ago, 2000 let's say, it was common for developers of software to be so lazy that they didn't even know if their software worked. They wouldn't write unit tests, they wouldn't even bother testing their code. They would throw it over the fence to quality assurance engineers and expect them to say, "Oh my god this is the greatest code ever, and it works perfectly". With the exception of the most simple program, this has never actually been the case, hell even [Grace Murray Hopper](http://en.wikipedia.org/wiki/Grace_Hopper) (go Brewers!) couldn't account for literal bugs in the system. This has often caused great angst among real engineers out there and even today people in the Software industry continue to say that Software engineering [is not "Real Engineering"](http://elegantcode.com/2011/06/22/why-software-development-will-never-be-engineering/). This is too easy of a copout and let's people off the hook for designing bad software, or using bad techniques.

# It's not like we're building Bridges!

This is a classic argument. Bridges are ridged and have to be designed up front to meet the engineering requirements to span what they are being built for. They are static entities that never change, right? Well, that's not totally accurate, even great engineering feats aren't perfect and need to be fixed, look at the new eastern span of the Bay Bridge. There are a bunch of issues that weren't properly accounted for and [now need to be fixed](http://www.sfgate.com/bayarea/article/Plague-of-problems-puts-Bay-Bridge-seismic-safety-6253577.php). So, bridges aren't perfect, and need to go back and be fixed, sounds a lot like software. To try and match the way that buildings and bridges are engineered, the Waterfall Method was created (I remember this being taught to me in college as the new cool awesomeness for development). It really seemed like the greatest thing ever.

Years later I started working at a large company, when I got there they hadn't shipped their planned release for over a year. It was stuck in this cycle of Dev -> QA -> Dev -> Product -> Dev -> QA that was never ending. So this was first hand experience of this awesome technique that I was taught in college, and it's abject failure to deal with real world issues. What's the problem? Software has a million moving parts. It's dynamic by nature. This is why the Bridge analogy breaks down so quickly, but it's just the static bridges that don't match this. Not all bridges are made this way, check out the [living bridges in India](http://www.grindtv.com/random/exploring-the-living-bridges-of-india/#h7UqtAgwrSothwuX.97).

![Living bridges](http://static.grindtv.com/images/1/00/40/80/06/408006.jpg)

What's my point? The issue with Software Engineering isn't that it's not actual engineering, it's that it's Dynamic Engineering. It's constantly adapting and changing to new uses and needs. When you built that website tool it only expected one user at a time, then it blew up and you had like a whopping ten, so you decided it needed to run in parallel. Did you go back and rewrite the entire thing? No, you went back and made it parallel so that all those ten people weren't waiting on each other when they went to your site. Now of course we deal with thousands of connections at a time in an application and so that simple synchronization you did needs to give way to optimistic locking and atomic reads/writes to drastically increase the performance of your application. No locking; again, did you rewrite the entire thing? No, you fixed the weak spots (well unless you wrote it in Ruby and realized that you needed it to actually run fast).

# Along came TDD

I remember when Test Driven Development came around. If you know all your inputs and outputs, you can just write the tests for it and then the code will just flow to match your test cases. The problem with this is it shoves Software Engineering back into this idea that it is static and non-changing. The one case I've found it useful is parsing and finite-state-machines, you know all the inputs and expected outputs, so it really does help you validate and write your code faster (let me know if you know of other really good fits). In most cases though, you actually don't know what your inputs are until you design the interface and then try to write the code behind it, only to discover that the interface you designed doesn't allow for nice code to be written after that. In fact, I have found TDD to actually be about as slow as Waterfall in terms of delivery. Ok, so TDD doesn't work, but it did pass on something really important, Test *Oriented* Development. This term is rising in popularity, but what it means is that the code you write is easily tested through the use of Mocks and Unit tests. So why is this an important development in the field? It shows that there is a discipline to coding, and technique which allows for software to be verified to be correct within whatever bounds you've declared. Ok, now we're getting closer to becoming engineers.

# Dude, where's my Bridge?

In the American Civil War (War of Northern Aggression for you Southerners) the Confederate army burned many railroad bridges to try and slow the advance of the Union armies. The [Trestle bridge](http://usmrr.blogspot.com/2010/10/haupts-military-bridge-w-trestles.html) construction was used to build bridges quickly and reliably in order to get the Union trains moving. So this is where we come to software as components in a larger system. Object-Oriented design, code reuse, I'll avoid Microservices for right now, maybe a future post. The point is that Components, like the trestle, allow for systems (bridges), to be built faster. The nice thing about this is that like an individual trestle, any component that fails or needs to be changed can be done so without rewriting the entire system. Components must have strong interfaces by which it is known which is in use in software (one reason why I've been attracted to OSGi in the past). So we can build bridges with individual components because each one can be verified individually before inserting into the whole. Unit tests on your components that cover what the expected input and outputs of the components mean that now you have a easy method of verifying a rewrite of that component, and any future rewrites after that.

# So am I an engineer?

I build things, I follow strong rules about how I build these things, and I verify that the things I build are correct and fully functional. The entire point of writing this is that I find it annoying that people keep saying that we software engineers are not engineers, that at best we're designers or worst hacks. This is also used as an excuse by lazy developers to not put in proper design and controls in the software they build. This is not true and it's possible to build software both quickly and with a regard to future changes when required. Agility is key and the organization needs to be amenable to Agile development methodologies, with constant iteration to hone in on the ideal system. I follow these rules when building software:

- Use Components to create strong [Separation of Concerns](http://en.wikipedia.org/wiki/Separation_of_concerns) and boundaries
- Unit and Functional tests to verify those Components
- All data is Immutable by default for ease of threading
- Any system operation or high level operation should be idempotent and/or atomic

What these allow me to do is follow fast iterative design. Create a quick top level design, use that to guide the development of each component down the stack. When guiding large architectures across teams, this is essential. Get initial code out as quickly as possible such that the real world stresses can be discovered and fixed as issues come up, and because you have test harnesses and good boundaries around your component it's easy (ish) to replace. I am a Software Engineer, I follow strong engineering practices around what I do, do you?

What I've left to the reader, proper test design (checkout [TestNG](http://testng.org/doc/index.html) for Java and [Mockito](http://mockito.org/)) and methodology, good Agile development methodologies (pick one). Do your own research.

*I decided to make this a three part piece. The next one deals with testing if you're interested in reading it. The final is about DevOPs*
