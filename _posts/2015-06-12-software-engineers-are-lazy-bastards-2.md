---
layout: post
title:  "Software Engineers are lazy bastards, pt. 2"
date:   2015-06-12 00:00:00 -0700
categories: dev software programming testing
---

*I decided to make this a three part piece. The first one is here if you're interested in reading it. It concerns componentization and following good practices when building software as an argument for Software Engineering as a legitimate Engineering field. In this post I'm going to cover proper testing that all Software Engineers should be following. The final post is on DevOps*

Let me start off by explaining why I am calling Software Engineers lazy. This stems from the general principle that people are going to generally do the least amount of work possible to accomplish a given task. Software Engineers are no different; Computer Scientists on the other hand are perfectionists always looking for the most elegant solution to a problem. Perhaps even creating a new theorem or axiom, it's my job as a Software Engineer to understand and utilize these new advancements (and perhaps one day I will create some, I did get a [degree in Computer Science](http://computerscience.vassar.edu/) after all). Like the [CAP theorem](http://en.wikipedia.org/wiki/CAP_theorem) or [Raft](https://raftconsensus.github.io/) consensus protocol, it's definitely my responsibility to understand the theories behind these and be able to implement them if necessary, but I look at these as things like `I` beams in construction that can be bought off the shelf. My job as a Software Engineer is to take disparate pieces of technology and put them together to build a larger system. But why are we inherently lazy? Corners will be cut in order to ship software, systems will have components that aren't complete, because we have limited time and money which constrains our abilities to be perfect.

In other worlds, the real world intervenes and so what we need to do is find a way to mitigate issues down the road. This is why I'm so adamant about componentization or modularization in my own code, and any team that I'm leading. If that piece isn't perfect, go back and refactor. This post isn't about that, what it's about is how to make each of those components as high quality as possible. But before that let's discuss the quality of airplanes.

# We need some chicken guns!

[Chicken guns](http://en.wikipedia.org/wiki/Chicken_gun), created in the 1950s to test the strength of different components of an airplane.

![Chicken Gun](http://www.sae.org/aeromag/techupdate_3-00/images/05b.jpg)

They're used to check the strength of both engines and windshields in the event that a large bird hits the airplane. It's exactly what it sounds like, a large pressure gun that shoots chickens at a high velocity to simulate a midair strike (like that potato gun you used to accidentally break the window of the garage at your friends house, no, not me...).  This is obviously important, you don't want to discover during flight with 150+ people on board that the windshield or engines can't withstand something that's fairly common in the air. So the chicken gun is used to make sure we're all safe in case of a mid-air strike with a bird. Cool right?

The [wingbend test](http://www.wired.com/2010/03/boeing-787-passes-incredible-wing-flex-test/) is used to make sure that the aircraft wings aren't going to fall off or apart in mid-flight. It's that fear you have in the back of your mind when the plane is bouncing around in crazy turbulence that one of the wings is just going to pop off and you all go spiraling down to your deaths. Aren't you happy that the wings will bend up to a degree that is so mindbogglingly extreme that you could try a [900](https://www.youtube.com/watch?v=4YYTNkAdDD8) like Tony Hawk on them? But even before this test, they already have subjected the aluminum composites being used to understand their tensile strengths. Testing all the way down to each panel before it's attached to the plane.

There are tons of tests that are run through before a plane can even fly. Checking that all the electrical systems, the flaps, etc., are fully functional. Then they actually take the plane into the air for a battery of [flight tests](http://news.travel.aol.com/2010/08/17/what-does-a-plane-go-through-before-it-can-fly/). These tests are critical to determine the safety of a plane. Now imagine for a moment that the tensile strength or longevity of the metal wasn't known before the flight test, that the pressures of the initial flight test shows that the internal ribbing of the plane needs to be replaced. How difficult would that be? How much more expensive is it to replace that at the end, than to realize it at the beginning and just choose a different material in the first place? Code quality should be treated in the same way.

# What is quality code?

This question is always answered in a lot of different ways. Years ago I was working on a project in which I needed to modify some of [DJB's](http://cr.yp.to/djb.html) code. He writes a quality of code that is impressive. C that's platform independent, big-endian and little-endian compatible. It was a really cool experience to see that amount of thought put into writing software, but I wouldn't say it's easy to grok. While I have the highest respect for what he's done, in my case what I think is just as important is writing code which is easily maintainable. Components help with this, but so do tests. A [friend](https://twitter.com/timkral) and former coworker of mine introduced me to this idea of a testing pyramid. For a basic overview of this, here's an ok [blog post](http://martinfowler.com/bliki/TestPyramid.html). I'm going to modify that in some important ways, especially since I'm not a UI developer, I won't go into UI testing at all (though I would suggest you need this same structure on the UI side, with actual [selenium](http://www.seleniumhq.org/) tests or similar at the top of the pyramid). I'm a backend systems architect, <sarcasm>when do I need UI</sarcasm>. But in the vein of fighting the lazy software engineer, I think it's important that we software engineers have built tests around each of these areas, here is the pyramid that I implement my code by:

![Test Pyramid](http://2.bp.blogspot.com/-FIeaL1qaJ48/VXtAzmLKzLI/AAAAAAAAAHs/8V1j1zmGoA4/s640/testing-pyramid%2B%25282%2529.jpg)

I'll run through each of these sections, but the important thing is that what this represents is that most of your test coverage occurs at the bottom of the pyramid, with ever smaller numbers of tests flowing to the top. From a code complexity standpoint though, the tests at the top of the pyramid are more difficult to write and maintain, therefor there should be fewer of them. I'll start from the bottom up, in fact I'll spend more time describing things bottom up too.

# Unit test your code, fool!

If you're not writing unit tests around every class you write, you are a fool. Yes, you are, I know you're saying, "but that's just a simple function that adds two numbers and returns the result". But if a function as simple as:

```java
int myAdd(int i, int j) {
  int k = i + j;
  return k;
}
```

still could have a bug! Hell, technically speaking you have an overflow problem that this isn't dealing with where i and j could be max ints and overflow the size of int. Also, it's just as easy to accidentally write 'return i;' and cause a bug in your most trivial code. I'm not suggesting to go crazy, just write a quick sanity test.

There is one rule that you must follow though when writing Unit tests, they must be clean of any external dependencies. Don't get stuck initializing a massive tree of dependencies, use Mocks for this stuff (if your a Scala or Java dev and you don't know [Mockito](http://mockito.org/), then learn it, right now, it will save your life). If you have to launch a DB to make your unit tests work, those are not unit tests (they are more likely functional or integration tests). So don't do that! You just slow down your development speed because you've made it harder to run your tests, and it takes longer to setup your development environment. I follow these rules on unit tests:

- No external dependencies (i.e. DBs, or other remote services)
- Don't require shared state between tests (or as little as possible)
- Always make sure your tests can be run in your IDE with no other actions needed than compiling
- Test all expected code paths in a method (i.e. you don't have to go overboard with exception cases)
- If it's expected to be multi-threaded, write some threaded tests (these are fun, and will teach you a lot about making your code testable)

By-the-way, a target of 80% code coverage is generally good for unit tests, more than that and you start making reformatting code more difficult. Also, more than this and there are diminishing returns on the tests themselves, you're aiming for checks to make sure your code is going to function properly in production, with tests based on real world issues. Unit tests are your base set of tests, they test the tensile strength of the materials which your later going to use to put together your larger project. Like the aluminum in the plane, if you discover issues this early in your development, your saving yourself a lot of pain (and time) down the road, and your lazy, right? You don't want to spend any extra time writing code than you need to...

(Quick aside, I dissed Ruby for it's speed in my first post on this, but to be fair the Rubyists really nailed tests living with your code. Rust has taken testing to another level where you can actually include tests in comments, and then have examples that are always confirmed to be uptodate with the code, super cool)

# But functional tests are way better!

Ok, not really. Functional tests are the next order of tests. As an example, this would be where you test your SQL against your DB (or NOSQL against your non-ACID whatever). Functional tests should only test one thing. I was working on a large project before that had a lot of various external components to work with, one being DNS. It used the dynamic DNS protocol to update the DNS records. First the DNS module was a distinct component in the code such that it had one responsibility, talk to DNS. The functional tests only tested this one component, they did not have any other side-affects, e.g. the DB code et. al. were not dependencies for the tests on this component. From our plane example, this is like the wing-bend test. The plane is put together, but specific functions are being tested to make sure it will be ok in the air, sadly I don't think Tony Hawk could skate on any of the code I've written.

Cool, but functional tests have side-affects, don't they? For DBs and DNS or similar persistent state systems, how do you make sure your tests are starting from a known state? Virtualization! VMs are cool, use them. Use Vagrant to setup your VM, use installation (RPM, DEB, Chef, Docker, etc.) scripts to install the packages, cache the installed VM (so that those steps aren't long in the future), and then clean up all persistent data in the VM before running your tests. It sounds like a lot of pain, but the advantages are awesome; you get to figure out at the beginning of your dev work how your going to install and bootstrap each system, and your guaranteeing that everyone testing is starting from a known point. Pretty awesome and saves you a ton of time later.

My rules for functional tests:

- One component is being tested
- Always start from a known state by cleaning up persistent information each time (at the beginning, not the end!)
- Install your external components now the way you plan to in the future (save yourself some time and heartache later, hell you might decide it's so ridiculously complex that you changed your mind about using it)
- Only test high level functionality, the unit tests cover code paths, these tests make sure that your assumptions about the thing your using are correct.
- What's great about these tests is that when you discover bugs in the interaction between your code and the external system (yes, there will be bugs this doesn't catch), you get to come back to these and replicate the bugs here. Isolated directly to just this one component without having to worry about other interactions, overtime hardening this component to ridiculous degrees.

# OMG, all my inter-team dependencies just got easier!

If you're following along, then you'll notice something that you just got for free here. Scrum teams are all the rage these days in large development organizations. If you follow these nice boundaries that your functional tests are helping to guarantee, separate scrum teams can actually work on separate components that will be more likely to work together in the end. It allows those inter-dependent teams to pull in each others tests early and use them to help with their integration tests early. Great for helping deliver code faster in larger organizations. This will make your manager really happy, because they get to focus on all that HR stuff instead of technical problems (which is what they love, right?). And happy managers => promotions => more money => happy and lazy software engineer.

# Ok, but I still don't know if my whole system works

Yeah, this is getting repetitive. Integration tests are similar to functional, but this is where you bring things together to make sure they all work. Essentially this just makes sure that when you put your DB in place and your DNS service in place that calling your REST API endpoint actually flows through each component and performs the action you expect. And why is this easy to set up? I know it sounds tedious, but you already have your VMs from your functional tests, reuse them! And again, you get to validate your assumptions about how all of these things will interoperate and what connectivity you need between them before production. Again cool, right?

Rules are the same as for functional tests, but for this you are writing a very minimal set of tests. This is the only place where you do end-to-end tests, in the plane this is akin to the full system tests performed before the flight tests.

# Do we get to fly yet?

Ok, yes, you can fly now. Smoke tests, these validate that your system, after being deployed in production, is working as expected. I used to think that it's enough to run these post deployment only, but then I realized something, there are all sorts of monitoring pieces that need to run constantly to make sure your application is actually working. Use your smoke tests for your monitoring needs! What's the difference between these and integration tests you ask? Not much. The only rule here is that your smoke tests should not damage your production systems, so design your system and the tests to not over time take down your production instances. Oh, and guess what, you can virtualize your system just like you did for your integration tests to test these locally as well. Virtualization is an excellent way of validating your stuff before ever hitting a real deployment, and you can do it while sitting on the beach disconnect from a network on your laptop. If your not using VMs to test your deployment steps, then your just making it harder on yourself to verify this since you'll need to share time on actual full test beds or production.

# But I'm a lazy bastard, remember?

So here's the key to getting to be lazy. What's harder, replacing the ribbing on the plane after it's built, or when you actually choose that material initially? It's the same here, if you have to track down crazy bugs because you never figured out if your stuff actually does the right thing at the most basic levels, debug time in production is much harder. You also didn't give yourself an easy place to replicate production issues to verify a fix before releasing. We've all been there, logging into production systems at 3am trying to figure out what's wrong with the damn system, definitely not lazy, compound that with an enterprise system where you as a developer are not even allowed to touch the production system, so you have to ask someone with production access to check stuff for you, all over the phone (or similar remote technology, because you were happily sleeping at home when this random problem just caused the entire site to crash and of course it was on your on-call night and you'd much rather get back to that dream and sleeping in, and oh my god now I have kids and they'll be up to less that two hours because debugging a system through someone else has already wasted an hour and you've only just gotten the heapdump, because it had to be uploaded to a safe directory so that you could download it, because you're not allowed to log into production! This is definitely not lazy). Remember, at each layer of the pyramid it is more difficult (and thus affects your ability to be lazy) to debug and fix issues as you get higher up the pyramid's stack. So the moral? Don't be lazy at the beginning and skip your testing, be lazy at the end when it all just works. And yes, even after all of this, eventually there will be a battery that ended up catching on fire for (initially) [no obvious reason](http://en.wikipedia.org/wiki/Boeing_787_Dreamliner_battery_problems). At least it wasn't the engine blowing up mid-flight...

*In the third part of this series I'll get into development's relationship with operations, yes, DevOps.*


<script type="text/javascript" src="//www.redditstatic.com/button/button1.js"/>
