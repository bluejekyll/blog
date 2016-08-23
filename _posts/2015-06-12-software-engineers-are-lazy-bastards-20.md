---
layout: post
title:  "Software Engineers are lazy bastards, pt. 3"
date:   2015-06-23 00:00:00 -0700
categories: dev software programming testing
---

*I decided to make this a three part piece. The first one concerns componentization and following good practices when building software as an argument for Software Engineering as a legitimate Engineering field. The second covers proper testing that all Software Engineers should be following. In this post I'll talk about Development and Operations, i.e. DevOps.*

Ok so DevOps became a thing. If I understand it properly, which I'm sure lots of people will say I do not, it's the idea that proper development practices are brought to bear on operations problems. This means things like using source code management systems (Git), having code reviews, following a process around work that needs to be done. These are all great things, and it's way better than way that people did this before. But here's the irony, and something I find kinda sad, computers and software were built to automate things. They were built to run factories, to make it easier to compute flight paths, to help with order fulfillment; I'm not going to list out all the places they help, I hope you get the point. So the irony is that DevOps is needed to help automate the systems that we (Software/Hardware/Computer People) built to help automate away other issues. I can't be the only one who sees this as ironically sad. To really make a point here, I'm going to start with an analogy, trains.

# Remember how complicated it was to drive a steam train?

Yeah, me too. You had to fill it with coal or wood, or whatever combustible thing was available at hand. And it was really hot, always sweating, that's why I stopped being and engineer and became a lazy software engineer. Ok, not funny, but still steam trains were really hard to operate. Look at all these dials and levers:

![Steam train](https://upload.wikimedia.org/wikipedia/commons/c/c5/4017_Backhead_20040426.jpg)

I'm going to guess that the big red lever is the brake (no, no, the one on the right not the left), Oh, and the dial on the left makes it go faster (the heavily used looking one). But seriously, I have no idea. The only thing I'm pretty sure of from this photo is where you put the fuel, and I'm guessing coal.

So, why am I talking about trains as a Software Engineer who knows little to nothing about trains? Because that picture above is what us lazy software engineers have been giving the operations folks for years. In fact, operations became so complicated that the operations folks needed to adopt development methodologies to manage systems at scale, and thus was born DevOps. Which is a great thing, using good standards in operations like SCM, releases of tools, declarative systems, etc. these are all great advancements, but why haven't they always been there? And why are they needed? Because as developers we've given operators so many dials to properly run our software (think on every config your require someone to write, every command line option...).

# DevOps should not be necessary

I blame Java for the state of the world (don't get me wrong, I still love Java though Scala is growing on me as a JVM language). Java and many of the interpreted languages out there put us in a state where the developer actively divorced themselves from the system they were building software for. This was great for being able to build things faster, test it once and expect it to work the same on any platform you deploy to after that. I remember when I had to build a common client/server system in C++ with a network stack that was portable between Windows, Linux and SunOS on x86, amd64, and sparc. Having to build something that worked on all of those platforms and think about how it would run under COM in Windows, daemontools in Linux/SunOS was a major pain and caused a ton of bugs where some needed to be debugged after shipping the software to the customer. I do not want to go back to that, so these VM based languages are always going to have a place for portable code, but I do ask myself this question all the time; Do I need portability? I have only shipped software on one platform for the past 11 years, Linux. But I do think one day I'll probably end up needing to support BSD, so let's just say that I have no intention of supporting a non-POSIX OS from here on in my development career (enter interest in Rust). When software engineers experience the pain of running their own code, they will change it so that it's easier to operate. Why? Because at heart, they are lazy, they want to get back to writing code, not supporting this crappy thing in production. As a comparison, look at modern train controls, even I could probably figure out how to stop this or make it go faster:

![High speed train](http://s.hswstatic.com/gif/diesel-locomotive-controls-2.jpg)

The point is that Software Engineers have gotten lazy in how their code is deployed and run. There have been great advancements over the last four years in the operations world. Everyone has heard of Docker, some rkt, appc, LXC, LXD, etc, all of these are giving us lazy people easy methods of packaging our software. It's easier to implement actual deployment tests upfront now than any point in the past. You don't need to chroot, it's done for you; you don't need to do any port mapping, you can get a unique IP per container or VM; you don't need to guess about installation, you can use the installation tools to create the container image. What this means is that as a developer there is no reason anymore to hand these jobs off to anyone else to validate the functionality of your system. As a Software Engineer today you should know exactly how your software is going to be deployed, run, executed, what your data persistence requirements are, etc. You can not ignore this, and it's never been easier with all the tools that exist out there now. There are lots of methods, you should research what you want. I'll say this, I've been using LXC for over four years, and containers are the way to go. I can't be happier about the OpenContainer spec that was recently announced.

# Where is this train going?

I'm watching these things: CoreOS, rkt, Atomic, Nix. I think that Nix is probably going to be the standard way of declaring system dependencies in containers. I think Nix or Atomic (with OSTree) will be the standard way of managing the BaseOS, but CoreOS is probably good enough for now. Work with your operations or DevOps teams to make this possible, as it will help immensely down the road. In other words, the operating system and application environment should be completely declarative.


# Software Engineers are not actually lazy

I know I called software engineers lazy bastards, and that probably stopped half of them from reading these posts, but I actually don't think we're lazy bastards. We got caught up in the methods and complexities of the day and forgot to stay grounded. Basically if you want to be lazy, it's important to be lazy after your software is built and functioning properly. Which means to be a good Software Engineer you need to keep these three areas in mind when building software:

- Modular and Component based systems (pt. 1)
- Testing without relying on others (pt. 2)
- Design your software to be easily deployed and managed (pt. 3, this one)

If you make good decisions in each of those categories, most likely you'll get to go back to being lazy and working on what you really want, and isn't that ultimately everyone's goal?


<script type="text/javascript" src="//www.redditstatic.com/button/button1.js"/>
