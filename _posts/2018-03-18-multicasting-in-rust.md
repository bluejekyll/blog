---
layout: post
title:  "Multicasting in Rust"
date:   2018-03-18 00:00:00 -0700
categories: rust
---

*A brief post to help others multicast in Rust*

In 2000 at a small startup I joined after college, I had discovered multicast and realized it was an amazing network tool. A service I had built made it possible to discover CORBA services on the network and link them together. This was just before zero-conf started becoming popular through, Apple's Bonjour, mDNS, LLMNR, and many other technologies that were being standardized. It was a lot of fun, and ever since working with it I have always wanted to use it for more things.

Fast forward *a few* years to the TRust-DNS project; very early on in the project I decided I wanted to implement mDNS, multicast DNS, [issue #24](https://github.com/bluejekyll/trust-dns/issues/24). Finally I've had some time to do this and I have gotten to learn a bunch more about multicasting, especially the differences of implementations between macOS, Linux, and Windows (the three platforms supported by TRust-DNS). Also, this is the first time I've done any multicasting in IPv6, which is surprising in its nuanced differences.

## What is multicasting?

When sending IP packets on networks there are generally two different protocols used, UDP and TCP. TCP always operates point-to-point, meaning there is only ever one `src` (source) and one `dst` (destination). The `src` and `dst` are specified as a pair of IP address (IPv4 or IPv6) and a `port`. The reason TCP is point-to-point is that it is session oriented, meaning both ends of the connection maintain information about what packets have been sent or received and then will attempt to resend any that were lost. UDP on the other hand is fire-and-forget, meaning that when a UDP packet is lost, there is no attempt by the underlying protocol to resend the packet. There are four basic modes for sending packets on a network over IP:

- `unicast`: single `src` to single `dst` (TCP and UDP)

This is what most people are using when they are sending data between network sources. This is where packets are being sent from a `src` to a `dst`, and only those two things care about it. Mind you, there is nothing that prevents any router on any network in-between from looking at and doing whatever it wants with these packets (this is true of all IP protocols). You need to add TLS over TCP or DTLS over UDP to create any privacy of your packets (or similar), though you can't really hide the `src` and `dst` on packets. Even with network encapsulation over something like a VPN (virtual private network), the VPN knows the ultimate `src` and `dst`.

- `broadcast`: many `src` to many `dst` on a single network (UDP)

Broadcasting is basically a thing of the past, only available in IPv4 (IPv6 must use multicast). This is the last address in a network, for example `198.51.100/24` the last address is `198.51.100.255`. The most useful thing that uses it is DHCP for dynamically configuring your network information on your computer. Broadcasting can create a lot of congestion on networks that span routers or switches, which is one reason why networks tend to be kept limited in size and also scope.

- `anycast`: single `src` to one of many `dst` (TCP* and UDP)

Anycasting is used to generally allow for the geographical distribution of service end-points, for example DNS. With UDP when the order and sequence of the packets doesn't matter, this is generally easily configured. Basically, in `anycast` the "closest" `dst` will win, derived from weights configured across all of the routes. There is no guarantee that a packet will end up in the same place.

\* TCP relies on a stable `src` and `dst`, `anycast` addresses can be configured to be reliable for TCP, but it takes a lot of care.

- `multicast`: many `src` to many `dst` (UDP and RTP*)

Finally, the point of this post, multicasting gives the ability for many `src`s to deliver packets to many `dst`s. Similar to broadcasting, but it allows for these distributed packets to be delivered to more nodes than just the ones attached to the hosts network. Multicast attempts to reduce congestion by requiring services that wish to receive multicast packets to "join" a multicast address for interest. These joins are then announced to upstream routers, where different network address spaces define the scope or range up the network stack that these memberships should be announced (see [rfc5771](https://tools.ietf.org/html/rfc5771) and [rfc7346](https://tools.ietf.org/html/rfc7346) for IPv4 and IPv6 registrations). This is to help prevent floods of multicast traffic hitting the internet at large. For our uses, you'll see that mDNS is defined to operate on `224.0.0.251` and `FF02::FB`, both of these are defined to be `link-local` multicast addresses, meaning they should not leave the local network (similar to the restriction on `broadcast`). This post isn't meant to be restricted to multicasting in mDNS, but that is what inspired this post.

\* RTP, [real-time protocol](https://en.wikipedia.org/wiki/Real-time_Transport_Protocol), is a new protocol implemented over UDP mainly for audio and/or video delivery. [WebRTC](https://webrtc.org/architecture/) being a major use-case. RTP can be used over multicast, but I personally haven't done anything with it, so can't comment much more about it's potential or the implementation details as they relate to multicast.

## When should you use multicasting?

Whenever you need to deliver the same data to many destinations. In mDNS what is being delivered to all nodes on the network is a query, and also announcements of new services on the network, you can read more details in [rfc6762](https://tools.ietf.org/html/rfc6762), specifically section 5. When dealing with `link-local` multicast, this is generally going to be ok. Be aware that many networks configurations make it difficult to multicast beyond the `link-local` network, so good luck.

You should be careful when deploying multicast software that spans networks. As networks of systems grow, the amount of traffic associated with multicast starts growing exponentially very quickly. Thought should be put into how this traffic can be reduced, for example, sections 7 and 8 of rfc6762 have suggestions for this in mDNS.

## Multicasting in Rust

Multicasting is not very different from standard UDP. There is a sender and a receiver, the `src` and the `dst` as normal. The difference being that the desitination IP address being sent to is a multicast address `224.0.0.0/4` IPv4 or `ff00::/8` IPv6. Those are large network spaces, and the [Wikipedia](https://en.wikipedia.org/wiki/Multicast_address) article does a decent job of explaining what they are for. There are some caveats though; while IPv4 will generally just work, IPv6 requires you to specify the interface on which you send the multicast packets (I'll get to this further on).

In general if you want to both send and receive multicast packets, you will need to create two sockets, one for outbound multicast packets, and one for inbound. We'll go through this process by first creating the multicast receiver. And then move on to the sender. The stdlib of Rust does not yet have all of the multicast options needed, so we need to turn to another library. We'll be using the `socket2` library which exposes the necessary options from `libc`. One thing that surprised me while working on this support in TRust-DNS was that I ended up being the person who had the pleasure of adding the IPv6 multicast socket option bindings to `libc` and `socket2`, which is surprisingly easy! If you notice things missing while you're working on similarly low-level features, you should definitely not be put off by process or working with the maintainers to get those changes in.

For the rest of this post, this repo has the complete project and a step-by-step commit history: [bluejekyll/multicast-example](https://github.com/bluejekyll/multicast-example)

### Getting the basics out of the way

Add the dependency on `socket2` in your Cargo.toml:

```text
socket2 = { version = "0.3.4", features = ["reuseport"] }
```

We need a minimum of `0.3.4`, which contains all of the IPv6 options and also a bug fixed. The `reuseport` feature is going to enable `SO_REUSE_PORT` on Unix systems. This feature should work on recent versions of Linux and BSD systems. It *may* work in the Windows Linux environment. This is going to allow us to "share" the multicast address and port on which we'll be listening. I don't get into the details of this in this post, but this is useful if you want many multicast listeners on the same host.

Next in your `bin.rs`, `lib.rs`, or `main.rs` we'll externalize the crate for usage in our program:

```rust
extern crate socket2;
```

Ok, so now we have our nuts and bolts.

### Setting up some boiler plate

TRust-DNS uses Tokio, but I'm going to leave tokio out of these examples and use blocking IO to keep everything simple. The initial socket creation is identical, but the operations would be wrapped in futures, just know that everything is basically the same. 

Let's pick a couple of addresses for our tests. We're going to use `link-local` scoped addresses. `224.0.0.123` and `FF02::123` should be available, and let's choose a randomish port, `7645`. I'm going to bring in `lazy_static` crate as well so that we can create static references to these addresses.

Cargo.toml:

```toml
lazy_static = "1.0"
```

and `lib.rs`:

```
#[macro_use]
extern crate lazy_static;
```

`lazy_static` relies on a macro for it's static construction which is why we need this.

Now let's define the static fields in our `lib.rs`, at this point we'll have:

```rust
#[macro_use]
extern crate lazy_static;
extern crate socket2;

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

pub const PORT: u16 = 7645;
lazy_static! {
    pub static ref IPV4: IpAddr = Ipv4Addr::new(224, 0, 0, 123).into();
    pub static ref IPV6: IpAddr = Ipv6Addr::new(0xFF02, 0, 0, 0, 0, 0, 0, 0x0123).into();
}
```

Rust's stdlib can test that the addresses are in the right scope for our use. Let's start building up our test cases:

```rust
#[test]
fn test_ipv4_multicast() {
    assert!(IPV4.is_multicast());
}

#[test]
fn test_ipv6_multicast() {
    assert!(IPV6.is_multicast());
}
```

Now if you run `cargo test` we'll see that at least our addresses are in scope. Now let's add the listener. First we're going to start with our boiler plate for the thread:

```rust
use std::sync::{Arc, Barrier};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};

fn multicast_listener(
    response: &'static str,
    client_done: Arc<AtomicBool>,
    addr: SocketAddr,
) -> JoinHandle<()> {
    // A barrier to not start the client test code until after the server is running
    let server_barrier = Arc::new(Barrier::new(2));
    let client_barrier = Arc::clone(&server_barrier);

    let join_handle = std::thread::Builder::new()
        .name(format!("{}:server", response))
        .spawn(move || {
            // socket creation will go here...

            server_barrier.wait();
            println!("{}:server: is ready", response);

            // We'll be looping until the client indicates it is done.
            while !client_done.load(std::sync::atomic::Ordering::Relaxed) {
                // test receive and response code will go here...
            }

            println!("{}:server: client is done", response);
        })
        .unwrap();

    client_barrier.wait();
    join_handle
}

/// This will guarantee we always tell the server to stop
struct NotifyServer(Arc<AtomicBool>);
impl Drop for NotifyServer {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

/// Our generic test over different IPs
fn test_multicast(test: &'static str, addr: IpAddr) {
    assert!(addr.is_multicast());
    let addr = SocketAddr::new(addr, PORT);

    let client_done = Arc::new(AtomicBool::new(false));
    NotifyServer(Arc::clone(&client_done));

    multicast_listener(test, client_done, addr);

    // client test code send and receive code after here
    println!("{}:client: running", test);
}

#[test]
fn test_ipv4_multicast() {
    test_multicast("ipv4", *IPV4);
}

#[test]
fn test_ipv6_multicast() {
    test_multicast("ipv6", *IPV6);
}
```

Ok that's a bit more code. What we're doing in that block in there is starting a thread that's going to run our server logic. We're making using of a `Barrier` to synchronize the server and the client such that the client does attempt to test before the server is running. We also have an `AtomicBool` for indicating when the server can safely stop running. I've also moved the client test section to a generic test case regardless of IPv4 or IPv6. Doing this makes testing client/server code easy.

When you run the tests you should see some decent output:

```console
$> cargo test -- --nocapture
    Finished dev [unoptimized + debuginfo] target(s) in 0.0 secs
     Running target/debug/deps/multicast_example-82a50da931778747

running 2 tests
ipv4:server: is ready
ipv4:client: running
ipv6:server: is ready
ipv6:client: running
ipv4:server: client is done
ipv6:server: client is done
test test_ipv4_multicast ... ok
test test_ipv6_multicast ... ok

test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

   Doc-tests multicast-example

running 0 tests

test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

Ok great, basics are out of the way. Now we can get on to the meat of the problem. Code in [test harnesses ready commit](https://github.com/bluejekyll/multicast-example/commit/a9c58409a72362605f2288397f41e0c93eefda6d)

### Creating the multicast listener

No we're going to build up our multicast socket. We'll be using the `socket2` library and not `std::net` for much of this. You can wrap `std::net` sockets in `socket2::Socket`, but we won't be doing that here.

```rust
use std::io;
use std::time::Duration;

use socket2::{Domain, Protocol, SockAddr, Socket, Type};

// this will be common for all our sockets
fn new_socket(addr: &SocketAddr) -> io::Result<Socket> {
    let domain = if addr.is_ipv4() {
        Domain::ipv4()
    } else {
        Domain::ipv6()
    };

    let socket = Socket::new(domain, Type::dgram(), Some(Protocol::udp()))?;

    // we're going to use read timeouts so that we don't hang waiting for packets
    socket.set_read_timeout(Some(Duration::from_millis(100)))?;

    Ok(socket)
}

fn join_multicast(addr: SocketAddr) -> io::Result<Socket> {
    let ip_addr = addr.ip();

    let socket = new_socket(&addr)?;

    // depending on the IP protocol we have slightly different work
    match ip_addr {
        IpAddr::V4(ref mdns_v4) => {
            // join to the multicast address, with all interfaces
            socket.join_multicast_v4(mdns_v4, &Ipv4Addr::new(0, 0, 0, 0))?;
        }
        IpAddr::V6(ref mdns_v6) => {
            // join to the multicast address, with all interfaces (ipv6 uses indexes not addresses)
            socket.join_multicast_v6(mdns_v6, 0)?;
            socket.set_only_v6(true)?;
        }
    };

    // bind us to the socket address.
    socket.bind(&SockAddr::from(addr))?;
    Ok(socket)
}
```

And we'll be adding the join into the `multicast_listener` function:

```rust
// socket creation will go here...
let listener = join_multicast(addr);
println!("{}:server: joined: {}", response, addr);
```

How about some more detail on each of those calls?

1) `socket.join_multicast_*(address, interface)`

This is the most important call, it tells the specified `interface` that you would like it to "join" the specified multicast group designated by `address`. If `interface` is IPv4 `0.0.0.0` or the IPv6 index `0`, then *all* interfaces will be joined to the multicast group.

2) `socket.bind(address)`

This is special, it expresses to the kernel that we are only interested in messages for `address`, i.e. it should filter out any other packets, at least this is how it works on Unix like systems. When we look at Windows we'll be coming back to this. The other option for this would be to bind to `0.0.0.0` IPv4 or `::` IPv6, but then we'd receive traffic on any interface sent to our port. By binding to the multicast group address we are saying to the kernel, we only want the multicast traffic.

And that's it, we now have a listener. Running the tests we should see:

```console
ipv4:server: joined: 224.0.0.123:7645
ipv6:server: joined: [ff02::123]:7645
ipv4:server: is ready
ipv6:server: is ready
ipv4:client: running
ipv6:client: running
ipv4:server: client is done
ipv6:server: client is done
```

Excellent, we are now joined to the multicast group. Code in [join_multicast commit](https://github.com/bluejekyll/multicast-example/commit/70e2426938806490b211a187be4cbe67872a74db)

### Wiring it all together

The next step is going to be to send some data to the server. So we'll create a new socket on the client to do this:

```rust
fn new_sender(addr: &SocketAddr) -> io::Result<UdpSocket> {
    let socket = new_socket(addr)?;

    if addr.is_ipv4() {
        socket.bind(&SockAddr::from(SocketAddr::new(
            Ipv4Addr::new(0, 0, 0, 0).into(),
            0,
        )))?;
    } else {
        socket.bind(&SockAddr::from(SocketAddr::new(
            Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 0).into(),
            0,
        )))?;
    }

    Ok(socket)
}
```

We're binding to any interface with the above, and a random port. Now we can send to the multicast listener (this replaces the section in `test_multicast`), [add sender commit](https://github.com/bluejekyll/multicast-example/commit/06e58e1ce47f29eb63d0f05cdb2a3aa8ceabf83e):

```rust
// client test code send and receive code after here
println!("{}:client: running", test);

let message = b"Hello from client!";

// create the sending socket
let socket = new_sender(&addr).expect("could not create sender!");
socket
    .send_to(message, &SockAddr::from(addr))
    .expect("could not send_to!");
```

And let's run tests:

```console
$ cargo test
...
test test_ipv4_multicast ... ok
test test_ipv6_multicast ... FAILED
```

On macOS the failure is due to `No route to host`. But why did it work for IPv4 and not IPv6? Well, it seems that at least on macOS the interface *must* be specified for IPv6. I need to look more into this, as this doesn't appear to be a requirement in many of the texts that I've read on the matter (and may have changed in recent OS releases). Digging around, the claim is that all you need is a route for the network, well:

```console
$ netstat -nr
...
ff02::%lo0/32                           ::1                             UmCI            lo0
ff02::%en0/32                           link#5                          UmCI            en0
ff02::%awdl0/32                         link#7                          UmCI          awdl0
```

That output claims that for our test address `FF02::123` we have three routes defined, so we *should* have a route. Please send me feedback if you see an obvious problem with my methods here, and have a solution. In any case, a workaround is to use `ifconfig -v` to get the index of the interface you want to use for IPv6. Then you can add this flag specific for multicast delivery:

```rust
/// to be consistent we'll add ipv4 default as well
socket.set_multicast_if_v4(&Ipv4Addr::new(0, 0, 0, 0))?;
...

/// and IPv6, this is specific to my machine
socket.set_multicast_if_v6(5)?;
```

What this essentially does is specify precisely which interface the multicast packets should be delivered on. For IPv4 that's just specifying the default. Now when we run the test both IPv4 and IPv6 tests should pass. [fix ipv6 outbound multicast commit](https://github.com/bluejekyll/multicast-example/commit/a2f8b90bf440a7f20993c82e04dbf24327eada33)

### Acknowledge receipt

Now we'll add the final piece to the puzzle, which is to respond to the message from the server. To do this, the multicast listener needs to read the inbound data, and then respond to it. This will require an additional socket. If you remember, we bound the listener's socket to the multicast address, which means we can't use it for delivering the response. But that's easy, we have our socket creation function, and since this is just for testing, we'll be wasteful and create a new socket for every response, note I changed `join_multicast` and `new_sender` to convert to and return `std::net::UdpSocket` to make some code simpler: [add response and validate commit](https://github.com/bluejekyll/multicast-example/commit/0b851c1f1466d2b0984f455f95c95c29deda3af6)

```rust
// test receive and response code will go here...
let mut buf = [0u8; 64]; // receive buffer

// we're assuming failures were timeouts, the client_done loop will stop us
match listener.recv_from(&mut buf) {
    Ok((len, remote_addr)) => {
        let data = &buf[..len];

        println!(
            "{}:server: got data: {} from: {}",
            response,
            String::from_utf8_lossy(data),
            remote_addr
        );

        // create a socket to send the response
        let responder = new_socket(&remote_addr)
            .expect("failed to create responder")
            .into_udp_socket();

        // we send the response that was set at the method beginning
        responder
            .send_to(response.as_bytes(), &remote_addr)
            .expect("failed to respond");

        println!("{}:server: sent response to: {}", response, remote_addr);
    }
    Err(err) => {
        println!("{}:server: got an error: {}", response, err);
    }
}
```

So now the server is getting the client's message *and* the server is responding to the message. We are responding to the client on the address received on this message. A side note here on trusting the UDP `remote_addr`: because UDP is not session oriented, just because the message through `remote_addr` claims to be from a particular host, this is by no means necessarily the case. If you want to read more about this, research reflection attacks and UDP source address spoofing. Back to this example, here are the important details:

1) `listener.recv_from(&mut buf)`

Receive the packet from the client into the allocated buffer we created first.

2) `Ok((len, remote_addr)) => ...`

On a successful receipt we're unwrapping the length of data received and the source address.

3) `let responder = new_socket(&remote_addr)`

Create a new socket for the response, in the proper IP scope.

4) `responder.send_to(response.as_bytes(), &remote_addr)`

Send our response to the source address. The response was a string passed in at the creation of the server, so the client already knows what is coming.

From here we can move on to the client to verify the server's response. A note, I realized that the `NotifyServer` was dropping early after getting to this point, so I changed that to capture the notify, and we're back in the `test_multicast` function:

```rust
let notify = NotifyServer(Arc::clone(&client_done));

// ...

socket.send_to(message, &addr).expect("could not send_to!");

let mut buf = [0u8; 64]; // receive buffer

// get our expected response
match socket.recv_from(&mut buf) {
    Ok((len, remote_addr)) => {
        let data = &buf[..len];
        let response = String::from_utf8_lossy(data);

        println!("{}:client: got data: {}", test, response);

        // verify it's what we expected
        assert_eq!(test, response);
    }
    Err(err) => {
        println!("{}:client: had a problem: {}", test, err);
        assert!(false);
    }
}

// make sure we don't notify the server until the end of the client test
drop(notify);
```

Now if you run the tests we should see successes, I'll limit it to just IPv4 so to shorten the output:

```console
$ cargo test ipv4 -- --nocapture
...
ipv4:server: joined: 224.0.0.123:7645
ipv4:server: is ready
ipv4:client: running
ipv4:server: got data: Hello from client! from: 10.0.0.195:56069
ipv4:server: sent response to: 10.0.0.195:56069
ipv4:client: got data: ipv4
ipv4:server: client is done
test test_ipv4_multicast ... ok
...
```

Excellent! We're done right?

## Supporting Windows

If you're happy with Unix only support you're done, but we're working in Rust, supporting multiple platforms is easy, right? Let's switch to Windows and see what happens! For this I grabbed a VM [from Microsoft](https://developer.microsoft.com/en-us/windows/downloads/virtual-machines) and installed the standard Windows Rust tools through [rustup](https://rustup.rs/) (make sure to go through a browser in the VM so that you get the correct link on the rustup site). I'm going to leave ipv6 up to the reader, so I'll just be running the IPv4 test:

```console
C:> cargo test ipv4 -- --nocapture
...
test test_ipv4_multicast ... thread 'ipv4:server' panicked at 'failed to create listener: Error { repr: Os { code: 10049, message: "The requested address is not valid in its context." } }', src\libcore\result.rs:916:5
...
```

Not valid in it's context, what? Well, I have the luck of having already worked through this with the TRust-DNS mdns support. It turns out Windows doesn't want you to bind to the multicast address like Unix. So we're going to make a platform specific construct here, we'll create a `bind_multicast` function that has two different implementations, one for Unix and one for Windows. By the way this command comes in handy when you're developing on something other than Windows and just want to check it if builds: `cargo check --tests --target x86_64-pc-windows-msvc`. In `join_multicast` we're going to replace the call to `socket.bind(&SockAddr::from(addr))?` with `bind_multicast(&socket, &addr)?` and then add the new function:

```rust
/// On Windows, unlike all Unix variants, it is improper to bind to the multicast address
///
/// see https://msdn.microsoft.com/en-us/library/windows/desktop/ms737550(v=vs.85).aspx
#[cfg(windows)]
fn bind_multicast(socket: &Socket, addr: &SocketAddr) -> io::Result<()> {
    let addr = match *addr {
        SocketAddr::V4(addr) => SocketAddr::new(Ipv4Addr::new(0, 0, 0, 0).into(), addr.port()),
        SocketAddr::V6(addr) => {
            SocketAddr::new(Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 0).into(), addr.port())
        }
    };
    socket.bind(&socket2::SockAddr::from(addr))
}

/// On unixes we bind to the multicast address, which causes multicast packets to be filtered
#[cfg(unix)]
fn bind_multicast(socket: &Socket, addr: &SocketAddr) -> io::Result<()> {
    socket.bind(&socket2::SockAddr::from(*addr))
}
```

All we've done is tell Windows to listen on all interfaces, but restrict it to the multicast port. We're still joining in the same way as before. You could limit this to a specific interface if you like, but that's up to the reader. But this is it, our code is now cross platform. What about IPv6? Well, I have to apologize. I can't seem to get IPv6 working on Windows, regardless of changing the target. I'll leave that to some intrepid Rustacean on Windows to figure out.

## Conclusion

Multicasting in IPv4 in Rust is straightforward. In IPv6 there are still some issues to work through, like finding an easy way to deal with the interface problem, and determining what is wrong on Windows. IPv6 leaves me dissatisfied, so I'll be continuing to look for solutions here. I'd love feedback from others who might know what, if anything, I'm doing wrong there. I ended up not getting into this in this post, but when multiple multicast listeners are on the same host for the same traffic, you will need to use `set_reuse_address` and `set_reuse_port` (where applicable) to allow for the listeners to use the same addresses.

I hope you enjoyed this post. Figuring all of this out for mDNS was a lot of testing, trial-and-error; the long list of commits is [here for the mdns_stream](https://github.com/bluejekyll/trust-dns/pull/337). The mDNS support is not yet complete in TRust-DNS but that mdns_stream (similar to what we did in this post) is the first step in getting there.

Thank you!