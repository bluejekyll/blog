+++
title = "The *new* TRust-DNS Resolver"
date = 2017-06-30
description = "Fun with the new TRust-DNS Resolver, and generally an update on the progress of the project"
aliases = ["/rust/2017/06/30/trust-dns-resolver.html"]

[taxonomies]
topics=["programming", "rust", "dns"]
+++

I released the initial version of the TRust-DNS Resolver recently. Version 0.1.0, the version is offset from that of the TRust-DNS library, which is up to 0.10.4 at the time of this writing. When I started this project my main goal was to make a DNS server which was easy to manage, and a client which could be used to manage it in a secure way. As I've marched forward in implementing all of the features I've wanted, it started becoming clear that people are more interested in the Client than the Server. It really struck me when I got issue [#109](https://github.com/bluejekyll/trust-dns/issues/109), "use the system's dns conf, e.g. /etc/resolv.conf"; of course what everyone really wants to use is a simple query interface to get IP addresses. The rest of this post is about building this initial version.

# What else has been happening

Since my last post I've been heads down at night on TRust-DNS. Writing posts hadn't really been at the top of my mind, but there have been a lot of new features and patches! TRust-DNS has gained support for TLS in that time, probably the other big feature. There are three variants supported: [OpenSSL](https://docs.rs/trust-dns/0.10.4/trust_dns/tls/index.html) by default; [native_tls](https://docs.rs/trust-dns-native-tls/0.1.1/trust_dns_native_tls/) which uses the host system's TLS implementation; and [rustls](https://docs.rs/trust-dns-rustls/0.1.1/trust_dns_rustls/) which is backed by the amazing [*ring*](https://docs.rs/ring/0.11.0/ring/) project. I made a claim in my previous post about the [Tokio](https://tokio.rs) framework which was that TRust-DNS would "... integrate easily with any code which also chooses to use tokio-rs." All of the TLS libraries I mentioned have Tokio wrappers, because of this it was actually simple to integrate them into the TRust-DNS library! It's exciting to know that Tokio really is as composable as it promises to be. I'm not completely done with TLS, when I finish up more support for mTLS in the Server and Client I'll post more information about that. On top of that, the DNSSec public and private key implementations have been cleaned up, and some fixes applied. Please see the Special thanks section below.

# DNS Resolvers

I had always planned to implement a full resolver in TRust-DNS, but it had never bubbled up to a high priority for me. As the Client has gained more users, the requests and confusion around using a raw Client made it clear that it was time to build one. At it's most basic a Resolver is responsible for going from a set of labels and resolving that to a set of records, following any NS[[1]](?#1) records as necessary until an SOA[[2]](?#2) is found for the zone. It also has the responsibility of following CNAME[[3]](?#3) chains until a final record is found. A Client is only responsible for the connection to a name server, the Resolver uses the Client to connect to as many name servers as necessary to fulfill a query on a set of labels (Name). As of now the TRust-DNS Resolver isn't recursive, it only sends a single request and relies on the upstream resolver for any necessary recursion.

*It's at points like this that it's worthwhile to mention that everything I know about DNS has been gleaned from operating and using DNS servers in various contexts and reading lots of RFCs. I have never in the past actually written a DNS server, a client, nor a resolver. So if you're reading this post, or any of my previous posts and notice that I've gotten something wrong, please file an issue in the [TRust-DNS repo](https://github.com/bluejekyll/trust-dns). Seriously, I won't be offended.*

# NameServerPool

There were some fun aspects of building this library. Probably the most interesting thing is the [NameServerPool](https://github.com/bluejekyll/trust-dns/blob/c7f6c59adb40c76bb954eaa543d03cefc0bbd70c/resolver/src/name_server_pool.rs), this is a simple pool for managing connections to a set of remote DNS servers. Most systems specify two DNS resolvers to use for resolution in the `/etc/resolv.conf` or similar. I thought it would be fun to track the performance of each connection and rank them as they are used. For this Rust has a nice [`BinaryHeap`](https://doc.rust-lang.org/std/collections/struct.BinaryHeap.html) in the stdlib. This a queue which allows for the connections to be ordered in priority order such that the highest priority item will be retrieved on the next call to the queue. Right now I'm not tracking a lot of information, just successes and failures at the moment (in the future I want to add latency as another):

```rust
#[derive(Clone, PartialEq, Eq)]
struct NameServerStats {
    state: NameServerState,
    successes: usize,
    failures: usize,
}
```

The `BinaryHeap` requires us to implement `Ord` and `PartialOrd` to return an Ordering of the elements in the queue:

```rust
impl Ord for NameServerStats {
    /// Custom implementation of Ord for NameServer which incorporates the performance of the connection into it's ranking
    fn cmp(&self, other: &Self) -> Ordering {
        // if they are literally equal, just return
        if self == other {
            return Ordering::Equal;
        }

        // otherwise, run our evaluation to determine the next to be returned from the Heap
        match self.state.cmp(&other.state) {
            Ordering::Equal => (),
            o @ _ => {
                return o;
            }
        }

        // invert failure comparison
        if self.failures <= other.failures {
            return Ordering::Greater;
        }

        // at this point we'll go with the lesser of successes to make sure there is ballance
        self.successes.cmp(&other.successes)
    }
}
```

This "algorithm" is quite simple. It says that if they are not equal, then the first thing is to compare the state of the connection, of which there are three: `Init`, `Established`, `Failed`. Connections that have never been established, i.e. they are in the initial state, will be [preferred](https://github.com/bluejekyll/trust-dns/blob/c7f6c59adb40c76bb954eaa543d03cefc0bbd70c/resolver/src/name_server_pool.rs#L45). After that whichever connection has fewer failures will be chosen. To try and introduce a little bit of load balancing after that, we choose the least successes. There are some obvious improvements that should be made to this. I'd like to come up with a better way of calculating weights, i.e. some numeric value that is computed based on all these inputs and spits out the highest priority connection. On top of that, it would be good to bucket failures and successes over different time periods such that a connection that initially failed is tried again and isn't permanently starved. For example, it would be interesting if you could list all the NameServers you want to use globally (say on a laptop), and the library transparently handles picking the best one.

To calculate these stats ends up being really easy with Futures, for example here's the `send()` method implemented on `NameServer`:

```rust
    fn send(&mut self, message: Message) -> Box<Future<Item = Message, Error = ClientError>> {
        // if state is failed, return future::err(), unless retry delay expired...
        if let Err(error) = self.try_reconnect() {
            return Box::new(future::err(error));
        }

```

The first thing we do (above) is check and see if the connection needs to be reconnected (TCP and TLS need this). This is an individual `NameServer` in the pool, if it's connected this is a noop. After that we grab references to the stats (stored in `Mutex`s for `Sync`), these are passed to the `and_then` and `or_else` Future result handlers:

```rust
        // grab a reference to the stats for this NameServer
        let mutex1 = self.stats.clone();
        let mutex2 = self.stats.clone();
        Box::new(self.client.send(message).and_then(move |response| {
            let remote_edns = response.edns().cloned();

            // this transitions the state to success
            let response = 
                mutex1
                    .lock()
                    .and_then(|mut stats| { stats.next_success(remote_edns); Ok(response) })
                    .map_err(|e| format!("Error acquiring NameServerStats lock: {}", e).into());

            future::result(response)
        })
```

In the above example the stats increment the success of the request, `and_then` will only be executed if the client returns on a successful query. Otherwise, we go to `or_else`:

```rust
        .or_else(move |error| {
            // this transitions the state to failure
            mutex2
                .lock()
                .and_then(|mut stats| {
                    stats.next_failure(error.clone(), Instant::now());
                    Ok(())
                })
                .or_else(|e| {
                    warn!("Error acquiring NameServerStats lock (already in error state, ignoring): {}", e);
                    Err(()) 
                })
                .is_ok(); // ignoring error, as this connection is already marked in error...

            // These are connection failures, not lookup failures, that is handled in the resolver layer
            future::err(error)
        }))
    }
```

Which of course tracks the failure. The `NameServerStats` object is a StateMachine, where `next_failure` actually transitions the connection into a `Failed` state. This all works with `BinaryHeap` because it exposes a method for performing a `peek_mut` where the wrapped value in a `PeekMut<T>` will be reprioritized in the queue after the reference is dropped. This is handled in the `NameServerPool::send` method:

```rust
    fn send(&mut self, message: Message) -> Box<Future<Item = Message, Error = ClientError>> {
        // select the highest priority connection
        let conn = self.conns.peek_mut();

        if conn.is_none() {
            return Box::new(future::err(ClientErrorKind::Message("No connections available")
                                            .into()));
        }

        let mut conn = conn.unwrap();
        conn.send(message)
    }
```

I did double check implementation of `PeekMut` to actually verify this functionality (and there is also a test case for it in `trust-dns-resolver`), I want to submit some improvements to the docs here in the stdlib. What's great about this implementation is that two async requests can be submitted back to back, and the highest priority connection will always be chosen, never actually removed from the pool! This is different from a database connection pool, for example, as everything is async; there is no need to remove and return connections to the pool, as you would with a synchronous connection to a database.

*A side note on `pub(crate)`*:

This is a really nice new feature in Rust for library maintenance. We've just reviewed some code above from two internal objects in the Resolver library. In the TRust-DNS client library, there are a lot of interfaces public that really don't need to be. The issue with this is that it increases the surface area that has been published from the TRust-DNS client library to include things that I really only want to be usable within the project. In the Resolver I get to use the new `pub(crate)` feature (introduces in [Rust 1.18](https://blog.rust-lang.org/2017/06/08/Rust-1.18.html)) which restricts the public interfaces to be only available within the crate. In affect this means that most internals (like `NameServer` and `NameServerPool`) of the Resolver library will not be public. This also helps because it will direct users to the interfaces I want them to use, namely: `Resolver`, and `LookupIp`. e.g.: 

```rust
pub struct Resolver {...}
```

vs. the internal only:

```rust
pub(crate) struct NameServer {...}
```

which is very nice. I do wish this had existed in the beginning, but it's great that it does now.

# What about DNSSec

I want TRust-DNS to always be validating DNSSec records, and reject unsigned records. This is actually one pillar of the project that I'm proud of; I'm still amazed it works to be honest... One thing I haven't been able to figure out is what to do with records that fail DNSSec validation. If this were a user application like `Firefox`, `Chrome`, or `Safari` then you would expect a dialogue warning the user, but that's not something I can handle for any downstream project. On top of that, the current implementation of the [SecureClientHandle](https://github.com/bluejekyll/trust-dns/blob/c7f6c59adb40c76bb954eaa543d03cefc0bbd70c/client/src/client/secure_client_handle.rs#L40) will strip invalid records from the return record set. This will not work for anyone that wants the option of using a record even if it failed validation. So my plan is to update the result from the SecureClientHandle to return validation failures in an Error variant. I'm of course open to other ideas, so please send them my way, I have [an issue](https://github.com/bluejekyll/trust-dns/issues/154) open for discussion.

# Work left to do on the Resolver

There are still a few things that need to be implemented in the Resolver:

* `AAAA` (IPv6) in addition to the `A` (IPv4) lookup performed today: *FIXED* [#159](https://github.com/bluejekyll/trust-dns/issues/159)
* Using the system `resolv.conf` for configuration: *FIXED* [#109](https://github.com/bluejekyll/trust-dns/issues/109)
* Connection latency measurements: [#158](https://github.com/bluejekyll/trust-dns/issues/158)
* Better fairness in the NameServerPool: [#157](https://github.com/bluejekyll/trust-dns/issues/157)
* Integrate TLS support: [#156](https://github.com/bluejekyll/trust-dns/issues/156)
* DNSSec validation: [#155](https://github.com/bluejekyll/trust-dns/issues/155)
* Fix SecureClientHandle to offer an error result of invalid RecordSets: [#154](https://github.com/bluejekyll/trust-dns/issues/154)

# Special Thanks

TRust-DNS has grown in complexity, supports multiple crypto libraries and multiple DNSSec algorithms, and three different TLS libraries. I tried to get this stuff correct when I wrote it originally, but for some of the variants I didn't have good public sites that I could reliably validate the code with, and getting the RFCs correct isn't easy. This is a special thank you to: [SAPikachu](https://github.com/SAPikachu) for fixing multiple complex issues in the library, SAPikachu has an impressive ability for tracking down and fixing opaque problems; [briansmith](https://github.com/briansmith) for fixing some issues in the storage of ED25519; [liranringel](https://github.com/liranringel) for the AppVeyor build support; [jannic](https://github.com/jannic) for fixing SIG(0) interoperability with BIND; and of all the other [contributors](https://github.com/bluejekyll/trust-dns/graphs/contributors). Your support is greatly appreciated, and has raised the quality of this project significantly. Also, I really couldn't have built this project with out the great work on Rust and the many [dependencies](https://crates.io/crates/trust-dns) upon which the project relies. If any of you will be at the [RustConf](http://rustconf.com) this year, please hit me up, I owe you each at least a drink of your choice. If anyone else will be at RustConf and wants to talk DNS, Tokio, Rust, or children and life; please find me there!

And of course a huge thanks to my wife, Lyndsey, and both kids who give me some time most days to work on this project and support me in everything else.

Thank you!

p.s. [@gcouprie](https://twitter.com/gcouprie/status/879975724937080832), I hope this one is up to your standards.

- <a name="1">1</a>) NS - Name Server records are pointers to other DNS servers which are known to be authorities for a zone in question. For example, `example.com.` has an NS record which points to `b.iana-servers.net.`

- <a name="2">2</a>) SOA - Start Of Authority record which defines some default values for the zone, every zone requires one to be valid.

- <a name="3">3</a>) CNAME - Canonical Name record acts as an alias for another record. A CNAME only aliases names, which means it can only act as an alias for one other record type, at the name of the CNAME record, there can only be one (except in DNSSec with regards to RRSIG records). This restriction is important now that we have A, IPv4, and AAAA, IPv6, records in a zone. It means that even if you are dual stack, you can't have a CNAME record which has an A and AAAA aliases at the same time. CNAMEs can also point to other CNAMEs, effectively creating a chain of names.