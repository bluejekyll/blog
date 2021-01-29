+++
title = "Taking TRust-DNS IntoFuture"
date = 2016-12-03
description = "Written to explain why I paused feature development of TRust-DNS to focus on implementing futures-rs and tokio-rs support"
aliases = ["/rust/2016/12/03/trust-dns-into-future.html"]

[taxonomies]
topics=["programming", "rust", "dns"]
+++

If you read my last post on TRust-DNS, [A year of Rust and DNS](http://bluejekyll.github.io/blog/rust/dns/2016/08/21/a-year-of-rust-and-dns.html),
 then you might be thinking, "why hasn't more progress been made toward supporting
 some more features in DNS?" The answer lies in this blog post, [Zero-cost futures in Rust](https://aturon.github.io/blog/2016/08/11/futures/). I read that
 and realized that much of the future work that I wanted to do on TRust-DNS would
 benefit from porting from [MIO](https://docs.rs/mio/0.6.1/mio/) to [futures-rs](https://docs.rs/futures/0.1.6/futures/) and [tokio-rs](https://docs.rs/tokio-core/0.1.1/tokio_core/). Also, since no one
 actually pays me for any of this work, I get to choose what to work on when,
 and what I think is the most important thing to deliver. This is such a huge leap for Rust that it was completely worth adding a couple of months to the delivery of new features.

This[[1]](?#1) is the story of the journey into the future; including the pain, the joy and some thoughts on the future. I will forewarn you that should you attempt to follow this path, things will probably have changed quite a bit during the time that this was written and when you attempt the journey. I should also mention, that I built most of this somewhat isolated from the on-going development around tokio-rs, so it's completely likely that I have made decisions that are not idiomatic according to people more deeply involved in that effort.

# What is Async I/O? (briefly)

To understand where we are going, you must first understand what asynchronous input and output (async I/O) is and why it is important. In network software (all I/O based software in fact), there are basically two forms of I/O. The standard one which people generally learn first is blocking I/O. In blocking I/O operations you write some code like:

```rust
let socket = UdpSocket::bind("127.0.0.1:52");
let mut buffer: Vec<u8> = Vec::with_capacity(512);

socket.recv_from(&mut buffer).unwrap();
```

That `recv_from(..)` is a blocking request. It will never return until there is data to receive from the socket, i.e. a packet arrives at the specified port. A big negative consequence of using blocking I/O is that in order to execute any other logic, a new thread would need to be created.

In non-blocking, async I/O there is a substantial difference: it will not block (hard to guess from the name I know); instead it will return immediately and tell you it's not ready. For example:

```rust
let socket = UdpSocket::bind("127.0.0.1");
socket.set_nonblocking(true);
let mut buffer: Vec<u8> = Vec::with_capacity(512);

loop {
  match socket.recv_from(&mut buffer) {
    Ok((_)) => /* do something with data */,
    Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
      /* do something while waiting */
      continue
    },
    error => return error,
  }
}
```

The code is more complex, but it has a special feature: instead of blocking you get the nice option of doing something else when there is no data ready. The really cool thing about this is that you can create two or more execution paths in your code, without threads. To learn more,  [Richard Stevens](http://www.kohala.com/start/) and his tomes on "UNIX Networking Programming" remain excellent reading in my opinion, there may be better resources now but I still pull those off the shelf from time to time. If your program is small, and not used much, then blocking I/O has traditionally been the easier thing to use, but to do anything concurrently you need to turn to threads. Threads are expensive, and when there are many of them, they can cause scalability issues due to resource consumption and context switching.

The holy grail is when async, non-blocking I/O becomes as simple to write as synchronous I/O, and tokio-rs is doing that for Rust.

# You said you had fun with MIO

Non-blocking I/O is the fundamental building block for asynchronous I/O operations, and subsequently, event driven systems. Many operating systems have higher order utilities for building event driven network software. POSIX defined `poll` and `select`, Linux has `epoll`, the BSD's use `kqueue`, and Windows `IOCP` (with which I am not personally familiar). These libraries provide an API for registering a lot of I/O handles, sockets, in a central place such that it's simpler to ask if any of those handles are ready in one system call.

MIO, metal I/O, is awesome because it's an abstraction over these different OS primitives. When I first used it, I was completely amazed at how seamlessly it works across all OSes. It's still a fairly low level interface, just one step above the others. In order to use it properly, it was important to build many state machines. Here is an example of the state machine for the [TCPListener](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/server/src/server/server.rs#L190):

```rust
impl DnsHandler for TcpListener {
  fn handle(&mut self, events: EventSet, _: &Arc<Catalog>) -> (Option<EventSet>, Option<(DnsHandlerType, EventSet)>) {
    if events.is_error() { panic!("unexpected error state on: {:?}", self) }
    else if events.is_hup() { panic!("listening socket hungup: {:?}", self) }
    else if events.is_readable() || events.is_writable() {
      // there's a new connection coming in
      // give it a new token and insert the stream on the event listener
      // then store in the map for reference when dealing with new streams
      for _ in 0..100 { // loop a max of 100 times, don't want to starve the responses.
        match self.accept() {
          Ok(Some((stream, addr))) => {
            info!("new tcp connection from: {}", addr);
            return (Some(EventSet::all()), Some((DnsHandlerType::TcpHandler(TcpHandler::new_server_handler(stream)),
                                                !EventSet::writable())))
          },
          Ok(None) => {
            return (Some(EventSet::all()), None)
          },
          Err(e) => panic!("unexpected error accepting: {}", e),
        }
      }
    }

    // this should never happen
    (Some(EventSet::all()), None)
  }
}
```

This is registered into an MIO event loop. I worked to come up with an abstraction with which I was happy. This needs to support building state machines for different protocols, currently just UDP and TCP are supported; there are other transits that I hope to support with TRust-DNS (of course, PR's are always welcome). You'll notice in the above implementation I'm dealing with the raw `events`. It took a little bit to get this logic correct, and I don't think there are any bugs in it. If there are bugs, it doesn't matter because I deprecated all the MIO based modules; they await the great executor of deletion. After reading about futures-rs and tokio-rs (which is built on top of MIO) I immediately recognized that there would be great benefits to switch to those tools. It paid off really well. Here is the [same logic](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/server/src/server/server_future.rs#L76) as above, but utilizing the tokio-rs `TcpListener` and the `Incoming` stream:

```rust
let listener = tokio_core::net::TcpListener::from_listener(..);

// for each incoming request...
self.io_loop.handle().spawn(
  listener.incoming()
          .for_each(move |(tcp_stream, src_addr)| {
            debug!("accepted request from: {}", src_addr);
            // take the created stream...
            let (buf_stream, stream_handle) = TcpStream::with_tcp_stream(tcp_stream);
            let timeout_stream = try!(TimeoutStream::new(buf_stream, timeout, handle.clone()));
            let request_stream = RequestStream::new(timeout_stream, stream_handle);
            let catalog = catalog.clone();

            // and spawn to the io_loop
            handle.spawn(
              request_stream.for_each(move |(request, response_handle)| {
                Self::handle_request(request, response_handle, catalog.clone())
              })
              .map_err(move |e| debug!("error in TCP request_stream src: {:?} error: {}", src_addr, e))
            );

            Ok(())
          })
          .map_err(|e| debug!("error in inbound tcp_stream: {}", e))
);
```

Actually, this isn't the same as the MIO based implementation. This implementation collapses two of the original state machines into one. It both accepts requests from the `TcpListener`, and also spawns a new Future to handle the newly established `TcpStream`. The TRust-DNS client was the first thing rebuilt on these new tools, which took a lot longer than anticipated. The payoff came when it literally took two nights to implement the new `ServerFuture`: one for UDP and the other for TCP.

While it may not be obvious at first glance, this implementation is both much simpler and also shows some very powerful features of building on top of tokio-rs. It's no longer dealing with raw events for one thing. Also, notice the wrappers around `TcpStream` (that's a TRust-DNS TcpStream), `timeout_stream` (will timeout if a TcpStream is inactive) and `request_stream` (deserializes bytes into DNS requests). Because everything is now based on futures-rs, it's now dead simple to combine different state machines to create awesome abstractions. Let me break this down a little more.

# The internal vs. external state of a Future

The `Future` trait in Rust follows the std libraries dedication to chained function interfaces. Let's take a look at a subset of it's function traits quickly:

```rust
pub trait Future {
    type Item;
    type Error;
    fn poll(&mut self) -> Poll<Self::Item, Self::Error>;

    fn map<F, U>(self, f: F) -> Map<Self, F> where F: FnOnce(Self::Item) -> U, Self: Sized { ... }
    fn and_then<F, B>(self, f: F) -> AndThen<Self, B, F> where F: FnOnce(Self::Item) -> B, B: IntoFuture<Error=Self::Error>, Self: Sized { ... }
    fn or_else<F, B>(self, f: F) -> OrElse<Self, B, F> where F: FnOnce(Self::Error) -> B, B: IntoFuture<Item=Self::Item>, Self: Sized { ... }
    fn select<B>(self, other: B) -> Select<Self, B::Future> where B: IntoFuture<Item=Self::Item, Error=Self::Error>, Self: Sized { ... }
    fn join<B>(self, other: B) -> Join<Self, B::Future> where B: IntoFuture<Error=Self::Error>, Self: Sized { ... }
}
```

These allow you to chain executions together based on the Future's success or failure. Some quick definitions, and then I'll show a practical use case:

- `poll()`- 'drives' the Future, i.e. check it it's complete
- `map()`- process the successful result of a Future and return some other value
- `and_then()`- on success, do something, then return a new Future
- `or_else()`- on failure, counterpart to `and_then()`
- `select()`- select this or another Future, whichever finishes first
- `join()`- join two futures waiting for both to succeed

While migrating TRust-DNS to tokio-rs those are the functions I found most useful. You should explore the [documentation](https://docs.rs/futures/0.1.6/futures/future/trait.Future.html) for more details.

Let's ignore `poll()` for a minute, the other functions allow for what I like to think of 'external state' to be captured in the processing logic after a Future yields a result. A good example of this is in [SecureClientHandle](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/client/src/client/secure_client_handle.rs#L106), which is responsible for <a name="proving">proving</a> a DNSSec chain:

```rust
self.client
.send(message)
.and_then(move |message_response|{
  debug!("validating message_response: {}", message_response.get_id());
  verify_rrsets(client, message_response, dns_class)
})
.and_then(move |verified_message| {
  // at this point all of the message is verified.
  //  This is where NSEC (and possibly NSEC3) validation occurs
  // As of now, only NSEC is supported.
  if verified_message.get_answers().is_empty() {
    let nsecs = verified_message.get_name_servers()
    .iter()
    .filter(|rr| rr.get_rr_type() == RecordType::NSEC)
    .collect::<Vec<_>>();

    if !verify_nsec(&query, nsecs) {
      return Err(ClientErrorKind::Message("could not validate nxdomain with NSEC").into())
    }
  }

  Ok(verified_message)
})
```

In this snippet from the function, it is using a [ClientFuture](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/client/src/client/client_future.rs), the TRust-DNS tokio-rs based DNS client, to send a query. Subsequent to a successful response  after sending the future query, it then validates all the resource record sets returned from the server. If the processing is also successful, it then checks to see if the responses were actually `NSEC` records, which then triggers additional logic to validate a negative cache response. Each of those operations `send(..)`, `and_then(..)`, `and_then(..)` captures the logic to be performed at each state transition, i.e. 'external state'. This is pretty cool, and I'm sure all you functional programmers are thinking "duh", but for me, learning to use this has been a very eye-opening experience.

Now Coming back to `poll(..)`, this is our internal state function. Sadly, most of my code here is fairly complex, you can take a look at [UdpStream](https://github.com/bluejekyll/trust-dns/blob/master/client/src/udp/udp_stream.rs#L113) and [TcpStream](https://github.com/bluejekyll/trust-dns/blob/master/client/src/tcp/tcp_stream.rs#L88)[[2]](?#2) for the actual inner I/O examples, but I don't want this post to be excessively long, so let's look at a simpler one, [TimeoutStream](https://github.com/bluejekyll/trust-dns/blob/master/server/src/server/timeout_stream.rs#L43):

```rust
pub struct TimeoutStream<S> {
  stream: S,
  reactor_handle: Handle,
  timeout_duration: Duration,
  timeout: Option<Timeout>,
}

impl<S, I> Stream for TimeoutStream<S>
where S: Stream<Item=I, Error=io::Error> {
  type Item = I;
  type Error = io::Error;

  fn poll(&mut self) -> Poll<Option<Self::Item>, Self::Error> {
    match self.stream.poll() {
      r @ Ok(Async::Ready(_)) | r @ Err(_) => {
        // reset the timeout to wait for the next request...
        let timeout = try!(Self::timeout(self.timeout_duration,      &self.reactor_handle));
        drop(mem::replace(&mut self.timeout, timeout));

        return r
      },
      Ok(Async::NotReady) => {
        if self.timeout.is_none() { return Ok(Async::NotReady) }

        // otherwise check if the timeout has expired.
        match try_ready!(self.timeout.as_mut().unwrap().poll()) {
          () => {
            debug!("timeout on stream");
            return Err(io::Error::new(io::ErrorKind::TimedOut, format!("nothing ready in {:?}", self.timeout_duration)))
          },
        }
      }
    }
  }
}
```

Ok, I realize I haven't mentioned [Stream](https://docs.rs/futures/0.1.6/futures/stream/trait.Stream.html)'s yet. Simply put, they are Futures which return more than one result: they return streams of results! I know - totally unexpected. For Java hacks out there, this shouldn't be confused with Java `Stream`s, which are more similar to Rust's [Iterator](https://doc.rust-lang.org/std/iter/trait.Iterator.html); oh, you shouldn't click that link, you will get jealous... in fact, can someone implement [this](https://github.com/bluejekyll/palindrome-rs/blob/master/src/lib.rs#L13) in Java Streams? I took a crack at it, and it wasn't obvious that it would be easy...

The `poll()` operation above simply does two things: it checks if the inner `Stream` is ready to yield data, or it checks to see if the timeout Future has expired. The entire point of this stream implementation is to guard the server against unused TCP connections. I'm sure the authors of tokio-rs will look at this and think there are better ways to implement this timeout, but this felt the cleanest to me (I would of course love feedback). In the case where there is data, the timeout is reset. If it did timeout, an error will be returned, and further up the stack the connection will be closed. For people unfamiliar with TCP, this can't be done with simple receive timeouts on the socket because those don't guard against a client which might be trickling data in over extended periods of time. This forces the client to send a full query a minimum of *X* number of seconds or the connection will be closed.

That's pretty cool, right? Or maybe I'm crazy for loving this stuff.

# To thread or not to thread?

So now that you have a complete and total understanding of tokio-rs and futures-rs, we can move to some really exciting topics, like, concurrency. At the very beginning, I mentioned that you could "do something while waiting" for a future I/O event to occur. This is where futures-rs has some really nifty stuff to offer. I/O and especially network I/O can take a long time (in CPU terms), which means there's lots of other stuff you can do in that time, like, more I/O! It blew my mind when I realized what `join()` and `select()` are in futures-rs, they are functions that actually allow for concurrent execution of code, but without threads! I bet you want to see an example. Let's look at the `SecureClientHandle` again. In DNSSec, there may be many `DNSKEY`s present in a zone. `DNSKEY`s are used to sign records and produce `RRSIG`s which are signed records for a particular resource record set. This might be a little hard to picture, so let's illustrate it with one:

![RRSIG proof graph](concurrent_rrset_proof.svg)

To trust the A records requires fetching each of the records back to the ROOT in order to validate it. TRust-DNS validates records from the bottom up (it can also be performed top down for public domains), the proof is *anchored* with the `ROOT CERT`. The public key for this certificate is available to anyone who seeks it; TRust-DNS compiles this key into the binaries. Any chain is valid, once you have a proof that all the records in the chain are signed back to a valid anchor. TRust-DNS allows for custom anchors to be associated with clients, as part of the Rust API (there is no `host` or `dig` binary for TRust-DNS yet, though I'd like to at least add `host` at some point).

The chain basically works like this: The ROOT zone, aka `.`, stores a `DS` record for any valid `DNSKEY` which the `com.` zone has registered. The [DS](https://github.com/bluejekyll/trust-dns/blob/master/client/src/rr/rdata/ds.rs) record is a hash of the [DNSKEY](https://github.com/bluejekyll/trust-dns/blob/master/client/src/rr/rdata/dnskey.rs), which is the public key associated to the private key used to sign RRSETs and produce the associated [RRSIG](https://github.com/bluejekyll/trust-dns/blob/master/client/src/rr/rdata/sig.rs), which is a cryptographically signed hash of the RRSET (the only thing that would make that run-on-sentence better is if it was recursive, which the proof algorithm is). In the above example there are two valid `RRSIG`s for the `www` resource record, `1` and `2`. These were produced by two different `DNSKEY`s, which both had two different `DS` records that validate those `DNSKEY`s and so on. `3` was signed with an invalid `DNSKEY`, there are legitimate reasons for invalid keys to exist in the wild (i.e. it's not necessarily a hacked domain or attempted man-in-the-middle): one case would be that keys are currently being rotated. Even though it might eventually be a valid key, `DNSKEY 3` can not be trusted, and `RRSIG 3` must be thrown away.

If you've read up to this point then I bet you're really excited for some code. Here is another snippet from [SecureClientHandle](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/client/src/client/secure_client_handle.rs#L147):

```rust
fn verify_rrsets<H>(
  client: SecureClientHandle<H>,
  message_result: Message,
  dns_class: DNSClass,
) -> Box<Future<Item=Message, Error=ClientError>>
where H: ClientHandle {
  let mut rrset_types: HashSet<(domain::Name, RecordType)> = HashSet::new();
  for rrset in message_result.get_answers()
      .iter()
      .chain(message_result.get_name_servers())
      .filter(|rr| rr.get_rr_type() != RecordType::RRSIG &&
      // if we are at a depth greater than 1, we are only interested in proving evaluation chains
      //   this means that only DNSKEY and DS are intersting at that point.
      //   this protects against looping over things like NS records and DNSKEYs in responses.
      // TODO: is there a cleaner way to prevent cycles in the evaluations?
                   (client.request_depth <= 1 ||
                    rr.get_rr_type() == RecordType::DNSKEY ||
                    rr.get_rr_type() == RecordType::DS))
      .map(|rr| (rr.get_name().clone(), rr.get_rr_type())) {
    rrset_types.insert(rrset);
  }

  // collect all the rrsets to verify
  let mut rrsets = Vec::with_capacity(rrset_types.len());
  for (name, record_type) in rrset_types {
    // collect the RRSET from the answers, name_servers and additional sections.
    let rrset: Vec<Record> = message_result.get_answers()
        .iter()
        .chain(message_result.get_name_servers())
        .chain(message_result.get_additionals())
        .filter(|rr| rr.get_rr_type() == record_type && rr.get_name() == &name)
        .cloned()
        .collect();

    // collect the RRSIG that covers that RRSET from the same sections.
    let rrsigs: Vec<Record> = message_result.get_answers()
        .iter()
        .chain(message_result.get_name_servers())
        .chain(message_result.get_additionals())
        .filter(|rr| rr.get_rr_type() == RecordType::RRSIG)
        .filter(|rr| if let &RData::SIG(ref rrsig) = rr.get_rdata() {
          rrsig.get_type_covered() == record_type
        } else {
          false
        })
        .cloned()
        .collect();

    // create the RRSET for evaluation.
    let rrset = Rrset { name: name,
      record_type: record_type,
      record_class: dns_class,
      records: rrset
    };

    debug!("verifying: {}, record_type: {:?}, rrsigs: {}", rrset.name, record_type, rrsigs.len());

    // push a VerifyRrsetFuture into the rrsets to validate.
    rrsets.push(verify_rrset(client.clone_with_context(), rrset, rrsigs));
  }

  // spawn a select_all over this vec, these are the individual RRSet validators
  // these occur in "parallel"
  let rrsets_to_verify = select_all(rrsets);

  // return the full Message validator
  Box::new(VerifyRrsetsFuture{
    message_result: Some(message_result),
    rrsets: rrsets_to_verify,
    verified_rrsets: HashSet::new(),
  })
}
```

There is a lot of code there; I've removed a bit, but I thought it would be interesting to see something more complex. This function is intended to be called as part of a function chain of a Future, if you [scroll up](?#proving) you can see where this is called, which means that this function and it's logic will only be run on a successful request. What happens here is that the `Rrset`s which need to be validated are collected with their related `RRSIG`s. These sets of futures from `verify_rrset` are then passed to `select_all()`, which is magic. It returns a `SelectAll` future which issues all of those proofs in parallel! This means that creating parallel execution blocks of events waiting for responses from I/O streams, in this case an upstream DNS server, is dead simple. There are still no threads, which is amazing! The abstractions with futures-rs will of course work with anything, not just I/O futures which tokio-rs provides.

I'd be remise if I didn't mention that in this example there isn't really a ton of concurrency going on. The reason for this is that in the context of the DNS client, only a single connection is being used. To reduce the number of queries being sent I implemented two Futures. One is [MemoizeClientHandle](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/client/src/client/memoize_client_handle.rs#L25) which will store/cache results from queries during a DNSSec evaluation. I don't want to add to the already significant amount of DNS traffic out there unnecessarily. That Future at it's core uses [RcFuture](https://github.com/bluejekyll/trust-dns/blob/7d3e56dec5cabdf2ff94278394954d13047b03bb/client/src/client/rc_future.rs#L13) which is a Future that will return copies of references to an inner future result, or the result if it's finished. `RcFuture` is a purely generic Future, which could be used in any other context. `RcFuture` makes the trade-off that it's cheaper to `clone()`, aka copy, the data than it is to query the data. The fact that I could just add these Futures as wrappers to existing logic, should make some of the benefits of these two libraries and the paradigm apparent.

# The future is now

These abstractions are excellent. By adopting futures-rs for TRust-DNS, and specifically tokio-rs, it means that these *should* integrate easily with any code which also chooses to use tokio-rs. Based on my experience, if you're doing I/O in Rust, you probably should be looking at using tokio-rs. Now, everyone is going to ask, "do you have benchmarks? I heard Rust is faster than a cheetah! Prove it!". Well, I [finally added](https://github.com/bluejekyll/trust-dns/commit/7d3e56dec5cabdf2ff94278394954d13047b03bb) some bench tests to TRust-DNS, with a test harness for running BIND9 as a comparison. Sadly, it turns out by just writing something in Rust you don't end up with the fastest program ever. The story of making TRust-DNS fast is not part of this post. You're going to have to wait until my next post where we can discover how to benchmark TRust-DNS, profile it, and then make it faster; the goal, of course, being to make it faster than BIND9. To be fair, I haven't been trying to make TRust-DNS fast. Until now I've been trying to make it correct, safe, and secure. Currently the server processes requests in 400µs.

If you want to play with the TRust-DNS futures, ClientFuture was [published](https://crates.io/crates/trust-dns) in the [0.8 release](https://crates.io/crates/trust-dns). The ServerFuture will be coming in 0.9, for which there is not yet a date, but probably soonish. 0.9 also will split the server and client into separate crates, so keep an eye out for that. I plan to implement DNS over TLS, multicast DNS and other things, which will all be simpler now, because I can have a single common high level interface for interacting with any of them. Fun, right? It has me dreaming of all the things that I did in the past, and how I can make them better in the future.

# Thank you!

Thank you to [@alexcrichton](https://github.com/alexcrichton) for helping guide me through some initial issues I had when implementing the UDP and TCP streams. Also, thank you to all of the contributors of [furures-rs](https://github.com/alexcrichton/futures-rs/graphs/contributors) and [tokio-rs](https://github.com/tokio-rs/tokio-core/graphs/contributors) who made all of this possible. A huge thank you to the [contributors](https://github.com/bluejekyll/trust-dns/graphs/contributors) of TRust-DNS; I deeply appreciate your efforts in helping drive this project forward.

- <a name="1">1</a>) Taking TRust-DNS IntoFuture is a pun, not a typo on the type [IntoFuture](https://docs.rs/futures/0.1.6/futures/future/trait.IntoFuture.html) in the futures-rs library.

- <a name="2">2</a>) I implemented these streams prior to [tokio_core::io::Framed](https://docs.rs/tokio-core/0.1.1/tokio_core/io/struct.Framed.html) being stabilized. I'd highly recommend looking at that for request/response type protocols.
