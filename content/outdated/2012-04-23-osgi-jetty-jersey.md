+++
title = "OSGi, Jersey and Jetty"
date = 2012-04-23
aliases = ["/java/osgi/jersey/jetty/2012/04/23/osgi-jetty-jersey.html"]
+++

*Since writing this, I do not recommend OSGi any more, just use [DropWizard](http://www.dropwizard.io)*

This is a mini how-to on setting up Jersey (JAX-RS) with Jetty running in OSGi. I wouldn't necessarily say that this the recommended setup, and I encourage comments for better ways of doing what I've done.

First off if you're not familiar with Jersey and JAX-RS, I'd recommend looking at it. It's a framework for developing RESTful applications using annotations and other methods to simplify deploying said applications. What's nice about this is you get to forget about all the boiler-plate code and just develop. Another cool feature is that if you write your code properly, then you can test it without the need of doing a full integration test (though, it's still a good idea to have those).

Ok, first step, make sure your web-app's bundle is setup correctly for Jetty, put this in your manifest:

```
Web-ContextPath: /bfry
```

The bfry being the root path of the web-app. When Jetty starts up, you should see some logs about the web-app being loaded. For this to work, in addition to the standard Jetty dependencies, I use these:

```xml
<dependency>
  <groupId>org.eclipse.jetty.osgi</groupId>
  <artifactId>jetty-osgi-boot</artifactId>
  <version>${jetty.version}</version>
</dependency>
<dependency>
  <groupId>org.eclipse.jetty.osgi</groupId>
  <artifactId>jetty-httpservice</artifactId>
  <version>${jetty.version}</version>
</dependency>
```

With that, your standard web-app should be loaded with your OSGi startup. Hooking up Jersey with OSGi takes a little more work. Your WEB-INF/web.xml file should be read by Jetty with the above config. This configuration will install Jersey:

```xml
<servlet>
  <servlet-name>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-name>
  <servlet-class>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-class>
  <init-param>
    <param-name>javax.ws.rs.Application</param-name>
    <param-value>benjaminfry.api.BenjaminFryApplication</param-value>
  </init-param>
</servlet>
<servlet-mapping>
  <servlet-name>com.sun.jersey.spi.container.servlet.ServletContainer</servlet-name>
  <url-pattern>/*</url-pattern>
</servlet-mapping>
```

What this says is that the BenjaminFryApplication (which I'll show you the code for below), should be the basis for the Jersey Container. There may be other (and perhaps better) ways to do this, but this works well for me. The Application is installed at /bfry/*, so all requests to this location will go through Jersey. Here's the code for the Application:


```java
package benjaminfry.api;


import org.apache.log4j.Logger;
import org.osgi.framework.BundleContext;
import org.osgi.framework.ServiceReference;


import javax.servlet.ServletContext;
import javax.ws.rs.core.Application;
import javax.ws.rs.core.Context;
import java.util.Collections;
import java.util.Set;


/**
 * This is the Jersey Application implementation for passing back references to the Jersey Resource handlers.
 *  In this example there are two resources, one is the LocationResource which implements the Location app.
 *  The other is the OSGiResource with is wired up with the OSGiService
 *  so that it has access to OSGi system. The LocationResource does not, so I won't show that one.
 */
public class BenjaminFryApplication extends Application {
    private static final Logger logger = Logger.getLogger(BenjaminFryApplication.class);


    private final Set<Class<?>> resourceClasses;
    private final Set<Object> resourceSingletons;


    /**
     * Constructor for the Application. This wires up all the Resources and stores the final map for retrieval
     *  at any point.
     * @param sc ServletContext is automatically passed in from the Jersey framework, this is used to retrieve the OSGi
     *           BundleContext which is specified by Jetty through its OSGi support.
     */
    public BenjaminFryApplication(@Context ServletContext sc) {
        try {
            BundleContext bundleContext = (BundleContext)sc.getAttribute("osgi-bundlecontext");
            if (bundleContext == null) throw new IllegalStateException("osgi-bundlecontext not registered");


            ServiceReference<OSGiResource> ref = bundleContext.getServiceReference(OSGiResource.class);
            if (ref == null) throw new IllegalStateException(OSGiResource.class.getSimpleName() + " not registered");
            OSGiResource osgiResource = bundleContext.getService(ref);


            resourceSingletons = Collections.<Object>singleton(meanResource);
            resourceClasses = Collections.<Class<?>>singleton(LocationResource.class);
        } catch (Exception e) {
            logger.error(e);
            throw new RuntimeException(e);
        }
    }


    /**
     * @return per request Jersey Resources which are used to create objects for handling the request.
     */
    @Override
    public Set<Class<?>> getClasses() {
        return resourceClasses;
    }


    /**
     * @return singleton Jersey Resources, these are pre-constructed objects, each one needs to be idempotent and
     *  thread safe.
     */
    @Override
    public Set<Object> getSingletons() {
        return resourceSingletons;
    }
}
```

In the above code there are some things to point out. The Jersey system supports different types of context information being passed in as parameters with the @Context annotation. The ServletContext has an attribute that is set by the Jetty OSGi system with the BundleContext for our OSGi Bundle. With this BundleContext we get a reference to the registered OSGiResource. The method getSingletons() is used by Jersey to get references to the Jersey REST Servlets. Each of these objects must be threadsafe, reentrant, etc.

Here's the code for the Jersey REST Servlet which also, through the use of OSGi Dynamic Services, is registered with the OSGi System:

```java
package benjaminfry.api;


import aQute.bnd.annotation.component.Component;
import aQute.bnd.annotation.component.Reference;
import benjaminfry.osgi.pub.OSGiService;
import com.sun.jersey.spi.resource.Singleton;


import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;


/**
 * OSGiResource is the Jersey resource for giving access to the OSGi Service.
 *  the path is bfry/osgi/*, anything outside this path will return a 404. This is defined as an
 *  OSGi DynamicServices Component which will instantiate the object and register it with OSGi automatically.
 */
@Component(provide = OSGiResource.class)
@Path("osgi/{myParam}")
@Singleton
public class OSGiResource {
    private volatile OSGiService osgiService;


    /**
     * Only registered the get method for retrieving the mean and variance for the specified httpCode.
     */
    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public String get(@PathParam("myParam") String myParam) {
        if (meanService == null) throw new WebApplicationException(Response.serverError().entity("osgiService is not set").build());


        String myValue = osgiService.getMyValue(myParam);
        return myValue;
    }


    /**
     * OSGi Dynamic Services reference for wiring up the osgiService.
     */
    @Reference
    public void setOSGiService(OSGiService osgiService) {
        this.meanService = meanService;
    }


    public void unsetOSGiService(OSGiService osgiService) {
        this.osgiService = null;
    }
}
```

This class has Jersey and Bndlib annotations intermingled, and yes it works. The @Component specifies that this application should be registered with OSGi. @Path is a Jersey annotation that specifies the location of this REST servlet, with the addition of the web.xml config from above it means this would be located at /bfry/osgi/{myParam}. The {myParam} portion tells Jersey that myParam is a path parameter (which can be a regex, look at the Jersey docs). The @PathParam tells Jersey which variable of the get() method to pass the path parameter to.

The lifecycle of this object works like this; The BenjaminFryApplication gets a reference to the OSGiResource service, this causes the OSGi environment to initialize the OSGiResource object to be initialized. During initialization, the OSGi Dynamic Services framework links up the field osgiService via the setOSGiService() method. When a request is made, Jersey looks up the path information say related to the request 'http://localhost/bfry/osgi/someParam'. Jersey sees the GET request, and calls the get() method based on the @GET annotation.

There are some cool things here, but the most interesting thing I think is that this "servlet" can actually be unit tested, no need for an integration test, because of the annotations. The unit test merely needs to construct the object, set either a mocked OSGiService implementation or a real implementation, and then call the get() method with whatever data you want to test. No need to start up Jetty at all for your tests! This makes testing the logic of the servlet simpler and the test itself more reliable. I'm not going to show this, it should be pretty obvious.

REST easy.
