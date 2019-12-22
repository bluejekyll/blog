---
layout: post
title:  "Await Trust-DNS no longer"
date:   2019-12-21 00:00:00 -0700
categories: rust
---

*A review of preparing Trust-DNS for async/await in Rust*

What started as a brief sojourn to learn the new `std::future::Future` in Rust 1.36, slowly became a journey to fully adopt the new async/await syntax in Rust. The plan had been to merely update to the new Future API, trying to keep the minimum Rust version as low as possible. This was ideally to keep the libraries compatible with more Rust users, but it became aparent that this wasn't really feasible. For a number of reasons, primarily, all of the underlying libraries Trust-DNS relies upon were moving in this direction, which made the task a fools errand. Additionally, adopting async/await simplified much of the code. This post is the announcement of the 0.18 release, representing a few months of work.

# Adopting async/await

Async/await has been a long awaited feature in Rust. It's such a massive game changer for the language. Low level async programming has traditionally always meant building state machines and abstracting the worflow of the system around them. The original version of Futures in Rust were no different, though the Futures library did help substantially by giving us predefined state machines for common scenarios.

It can be most easily shown how much more ergonomic this is from some code, here's an example from the previous release of Trust-DNS, the HTTPS request handler:

```rust
pub fn h2_handler<T, I>(
    handler: Arc<Mutex<T>>,
    io: I,
    src_addr: SocketAddr,
    dns_hostname: Arc<String>,
) -> impl Future<Item = (), Error = ()>
where
    T: RequestHandler,
    I: AsyncRead + AsyncWrite,
{
    // Start the HTTP/2.0 connection handshake
    server::handshake(io)
        .map_err(|e| warn!("h2 handshake error: {}", e))
        .and_then(move |h2| {
            let dns_hostname = dns_hostname.clone();
            // Accept all inbound HTTP/2.0 streams sent over the
            // connection.
            h2.map_err(|e| warn!("h2 failed to receive message: {}", e))
                .for_each(move |(request, respond)| {
                    debug!("Received request: {:#?}", request);
                    let dns_hostname = dns_hostname.clone();
                    let handler = handler.clone();
                    let responder = HttpsResponseHandle(Arc::new(Mutex::new(respond)));

                    https_server::message_from(dns_hostname, request)
                        .map_err(|e| warn!("h2 failed to receive message: {}", e))
                        .and_then(|bytes| {
                            BinDecodable::from_bytes(&bytes)
                                .map_err(|e| warn!("could not decode message: {}", e))
                        })
                        .and_then(move |message| {
                            debug!("received message: {:?}", message);

                            server_future::handle_request(
                                message,
                                src_addr,
                                handler.clone(),
                                responder,
                            )
                        })
                })
        })
        .map_err(|_| warn!("error in h2 handler"))
}
```

This example shows how the older Future combinators could be used together, but it made for somewhat complex code to write. The `async fn` version is much more straightforward: 

```rust
pub async fn h2_handler<T, I>(
    handler: Arc<Mutex<T>>,
    io: I,
    src_addr: SocketAddr,
    dns_hostname: Arc<String>,
) where
    T: RequestHandler,
    I: AsyncRead + AsyncWrite + Unpin,
{
    let dns_hostname = dns_hostname.clone();

    // Start the HTTP/2.0 connection handshake
    let mut h2 = match server::handshake(io).await {
        Ok(h2) => h2,
        Err(err) => {
            warn!("handshake error from {}: {}", src_addr, err);
            return;
        }
    };

    // Accept all inbound HTTP/2.0 streams sent over the
    // connection.
    while let Some(next_request) = h2.accept().await {
        let (request, respond) = match next_request {
            Ok(next_request) => next_request,
            Err(err) => {
                warn!("error accepting request {}: {}", src_addr, err);
                return;
            }
        };

        debug!("Received request: {:#?}", request);
        let dns_hostname = dns_hostname.clone();
        let handler = handler.clone();
        let responder = HttpsResponseHandle(Arc::new(Mutex::new(respond)));

        match https_server::message_from(dns_hostname, request).await {
            Ok(bytes) => handle_request(bytes, src_addr, handler, responder).await,
            Err(err) => warn!("error while handling request from {}: {}", src_addr, err),
        };

        // we'll continue handling requests from here.
    }
}
```

You'll notice that this code is much more straight forward and easier to read, flatter if you will. This is the big advantage of async/await, you can write code in a much simpler manner.

## Trust-DNS still has hand made State Machines

Trust-DNS has grown to 65 kloc with 41 kloc when excluding documentation (and there are still features to develop). Much of this has been in use for the past 4 years–rewriting it all to be async/await will take time, and isn't necessary to provide a new async/await API for the Resolver or other libraries. If you browse the code, this will be noticeable throughout. There are also some other reasons for keeping the hand made Futures, this is the fact that the Futures returned by an `async fn` is really just and impl trait. This signature:

```rust
async fn foo() -> Bar {...}
```

is for all intents and purposes equivalent to

```rust
fn foo() -> impl Future<Output = Bar> {...}
```

meaning that all the same limitations on usage of `impl Future` apply to the result of the `async fn`. One of those is that impl traits can not be named, e.g. it can't be stored as a field in a struct. This is easily worked around, as the type can just be boxed, and used as a dyn object, e.g. `Box<dyn Future<Output = Bar>>`. Alternatively, you can implement the Future yourself, and avoid the boxing. So there are still some potential advantages by not adopting `async fn`s everywhere, but those are rare.

## The ecosystem continues to advance

Trust-DNS has in many ways grown with the ecosystem around it. Initially it was built around the stdlib blocking IO apis. Once that POC was done, it was converted to use non-blocking IO with mio. After that as Tokio and Futures were developed in tandem, Trust-DNS adopted them early on and benefited greatly from those advancements. Now, Tokio and Futures have both been upgraded to also have async/await APIs, and they've become far easier to use because of it. It really is a great time to explore async IO in Rust. We know that people are excited, because the minute that the Trust-DNS Resolver supported Tokio 0.2 in 0.18.0.alpha.2, we saw a huge spike in [downloads](https://crates.io/crates/trust-dns-resolver).

Oddly enough, a feature of the Trust-DNS Resolver to make testing easier will also potentially make it easy to port other executors (like async-std). To facilitate decent tests in the resolver a trait was defined, `ConnectionProvider`. This trait allowed for the creation of mocked connections to test all the Resolver's logic, allowing us to test many different scenarios without actually introducing any network IO. This has the interesting side-effect of being useful for abstracting the underlying executor and network drivers–something for us to explore in the future.

Tokio itself has improved in a lot of other ways as well. The library has been polished significantly. There were some nuances to learn in adapting all of Trust-DNS to it, but all very much worth it. Please, explore the new API and I'd love any feedback you'd like to provide: [Trust-DNS Resolver](https://docs.rs/trust-dns-resolver).

## A Massive thank you!

I want to thank Lucio [@lucio_d_franco](https://twitter.com/lucio_d_franco) and Eliza [@mycoliza](https://twitter.com/mycoliza) for helping review so much of this. Additionally, I'd like to express my thanks to everyone who's contributed to Rust's async/await features, which are a spectacular achievement. To everyone who's contributed to Futures and Tokio, that was a herculean effort and it's really paid off, thank you! To all of the folks that continue to experiment with and contribute to Trust-DNS, this would not be possible without [you](https://github.com/bluejekyll/trust-dns/graphs/contributors). Lastly, thank you, Carl (@carllerche)[https://twitter.com/carllerche] for convincing me to "ship and fix later".