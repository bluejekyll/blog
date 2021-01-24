+++
title = "OSGi Classpaths and Jersey"
date = 2012-04-18
+++

*Since writing this, I do not recommend OSGi any more, just use [DropWizard](http://www.dropwizard.io)*

OSGi is cool, but it adds a ton of classpath constraints. I'll put up a complete OSGi page about some of the headaches I've run into and the basic setup I use at a later date, but today I want to share how to get rid of a ClassNotFoundException when trying to deploy Jersey.

If you're not familiar with Jersey it's an implementation from Sun/Oracle of the JAX-RS spec. Basically an annotation system in java for deploying rest based web services.

Anyway, this post isn't about that, it's about this:

```
java.lang.ClassNotFoundException: com.sun.jersey.spi.container.servlet.ServletContainer
 at org.eclipse.osgi.internal.loader.BundleLoader.findClassInternal(BundleLoader.java:513)
 at org.eclipse.osgi.internal.loader.BundleLoader.findClass(BundleLoader.java:429)
 at org.eclipse.osgi.internal.loader.BundleLoader.findClass(BundleLoader.java:417)
 at org.eclipse.osgi.internal.baseadaptor.DefaultClassLoader.loadClass(DefaultClassLoader.java:107)
 at java.lang.ClassLoader.loadClass(ClassLoader.java:248)
 at org.eclipse.jetty.webapp.WebAppClassLoader.loadClass(WebAppClassLoader.java:424)
 ...
 at org.eclipse.jetty.osgi.boot.OSGiAppProvider.addContext(OSGiAppProvider.java:232)
 at org.eclipse.jetty.osgi.boot.OSGiAppProvider.addContext(OSGiAppProvider.java:214)
 ...
 at org.osgi.util.tracker.BundleTracker$Tracked.customizerAdding(BundleTracker.java:439)
 at org.osgi.util.tracker.AbstractTracked.trackAdding(AbstractTracked.java:261)
 at org.osgi.util.tracker.AbstractTracked.trackInitial(AbstractTracked.java:184)
 at org.osgi.util.tracker.BundleTracker.open(BundleTracker.java:159)
 at org.eclipse.jetty.osgi.boot.JettyBootstrapActivator.start(JettyBootstrapActivator.java:118)
 at org.eclipse.osgi.framework.internal.core.BundleContextImpl$1.run(BundleContextImpl.java:711)
 at java.security.AccessController.doPrivileged(Native Method)
 at org.eclipse.osgi.framework.internal.core.BundleContextImpl.startActivator(BundleContextImpl.java:702)
 at org.eclipse.osgi.framework.internal.core.BundleContextImpl.start(BundleContextImpl.java:683)
 at org.eclipse.osgi.framework.internal.core.BundleHost.startWorker(BundleHost.java:381)
 at org.eclipse.osgi.framework.internal.core.AbstractBundle.start(AbstractBundle.java:299)
 at org.eclipse.osgi.framework.internal.core.AbstractBundle.start(AbstractBundle.java:291)
```

I'd been beating my head into the wall all morning when the problem/solution struck me. I'd doubled checked that I had these bundles installed and started (maven dependencies):

```xml
<dependency>
  <groupId>com.sun.jersey</groupId>
  <artifactId>jersey-core</artifactId>
  <version>1.12</version>
</dependency>
<dependency>
  <groupId>com.sun.jersey</groupId>
  <artifactId>jersey-server</artifactId>
  <version>1.12</version>
</dependency>
<dependency>
  <groupId>com.sun.jersey</groupId>
  <artifactId>jersey-servlet</artifactId>
  <version>1.12</version>
</dependency>
```

They were right there in the OSGi runtime: "Active". So what was up? The answer lies in how I was referencing the Jersey context in my web.xml:

```xml
<servlet>
  <servlet-name>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-name>
  <servlet-class>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-class>
  <init-param>
    <param-name>javax.ws.rs.Application</param-name>
    <param-value>com.my.Application</param-value>
  </init-param>
  <load-on-startup>1</load-on-startup>
</servlet>
<servlet-mapping>
  <servlet-name>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-name>
  <url-pattern>/*</url-pattern>
</servlet-mapping>
```

It turns out this is the only reference to the ServletContainer anywhere in my "code", in the web.xml. I use the maven-bundle-plugin for generating the bundles. The Bnd tool at the core of that plugin automatically collects all the Import-Packages from what's being imported in your Java code.

The classpath in OSGi is partly derived from your Import-Package statement, and since nowhere in my code was I explicitly referencing the ServletContainer, that class was never made available on the classpath.

Solution, changed the configuration of the maven-bundle-plugin to add the package to the Import-Package statement:

```xml
<Import-Package>com.sun.jersey.spi.container.servlet,*</Import-Package>
```

And then Jersey was deployed, and the world was calm.
