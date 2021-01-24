+++
title = "Easy Postgres extensions in Rust with pg-extend-rs"
date = 2018-12-27
description = "A project to make Postgres extensions in Rust easy, you might learn how to use macro_rules, attribute macros, allocators and some FFI in this post"
aliases = ["/rust/2018/12/27/announcing-pg-extend.html"]
+++

There were a few things that happened this year that got me excited for the possibilities of *stable* Rust entering new spaces. They all come in the form of APIs that have become stabilized with a lot of effort from all of the developers contributing to the language. I wish I could say I helped with that effort, I do get to exploit all of that effort in this new project. I want to express my thanks and greatest esteem towards the people who continue to push the language forward, making it more useful and more pleasurable to use. For me to be able to write this, the stabilization of procedural macros, custom allocators, and panic handlers were all necessary. Each of these was stabilized over the last year, thank you!

# Postgres extensions in Rust

Initially I started playing around with wanting to build Postgres extensions in Rust a while ago, but realized that there was a lot of unstable API work still being done in Rust that I dropped my initial efforts and focused on other things. That's all changed now! I started working in my spare time on this extension library a few weeks ago (which I may have use for in my day job). Building these tools today in stable Rust is possible because a lot of features have stabilized recently. I'm no Postgres internals expert, and have never written an extension for it before, but I decided to do this in the vein of fearlessly taking on problems with Rust.

## Goal

To build a library that makes it effortless to create Postgres extensions in Rust. This library needs to do a few things, which are currently implemented as C macros in Postgres header files, hey, my ancient knowledge of C continues to be helpful! As an aside, I still think people should learn C, and this is mostly because it remains the lingua franca for all foreign function interfaces (FFI) between different programming languages (and there's lots of software written in it out there, like Postgres).

First things first, we will need a macro to define the "module magic" that informs Postgres that a dynamic library is able to be loaded by it's loader. Next we need to create a way to call into Rust from Postgres such that we can write standard Rust code, without needing to know the inner workings of Postgres and it's conventions in C. This wrapper should also make sure that the FFI boundary is respected between the C and Rust. Finally, we will want to use Postgres' allocator `palloc` for allocating all memory in the extensions.

This might jump the gun a bit, but let's jump straight to the final code example (derived from [Postgres C-Language Functions examples](https://www.postgresql.org/docs/11/xfunc-c.html#id-1.8.3.13.8)):

```rust
use pg_extern_attr::pg_extern;
use pg_extend::{pg_sys, pg_magic};

/// This tells Postgres this library is a Postgres extension
pg_magic!(version: pg_sys::PG_VERSION_NUM);

/// The pg_extern attribute wraps the function in the proper functions syntax for C extensions
#[pg_extern]
fn add_one(value: i32) -> i32 {
    (value + 1)
}

/// Validate that the add_one function works in Rust as expected
#[test]
fn test_add_one() {
    assert_eq!(add_one(1), 2);
}
```

Follow the comments above which describe each important section to pay attention to, the full example is [available in the repo](https://github.com/bluejekyll/pg-extend-rs/blob/f3e5620a43d325b413a9d0c069bcc99b12505e1d/examples/add_one/src/lib.rs).

This is the way in which the function will be executed in Postgres:

```console
postgres=# SELECT add_one(3);
 add_one
---------
       4
(1 row)
```

## Prerequisites, we need the C bindings

Bindgen to the rescue! One of the greatest tools in the Rust ecosystem when building FFI code, is bindgen. We're going to use this to define bindings to the Postgres C types we need in Rust. To do this, in the `pg_extend` [crate](https://crates.io/crates/pg-extend), we're going to define a `pg_sys` [module](https://github.com/bluejekyll/pg-extend-rs/tree/f3e5620a43d325b413a9d0c069bcc99b12505e1d) and run bindgen in a `build.rs` [script](https://github.com/bluejekyll/pg-extend-rs/blob/f3e5620a43d325b413a9d0c069bcc99b12505e1d/pg-extend/build.rs).

I won't go over this in detail, bindgen has a great set of [documentation](https://rust-lang.github.io/rust-bindgen/) around it for generating FFI bindings to C. The headers we're using are from the `postgres/include/server`, and are defined in the `wrapper.h` [file](https://github.com/bluejekyll/pg-extend-rs/blob/f3e5620a43d325b413a9d0c069bcc99b12505e1d/pg-extend/wrapper.h).

## Defining pg_magic

The postgres magic macro, `pg_magic!(version)`, does a few different things. The primary goal is to tell Postgres that this is a module it can load. Secondarily, it also sets up some default global variables and functions. Before I display this, I should mention that I did look at the `pg_module` macro in [thehydroimpulse/postgres-extension.rs](https://github.com/thehydroimpulse/postgres-extension.rs), so I would be remiss if I didn't mention that it did help point me in the right direction. Let's look at what `pg_magic` generates, you can use the `cargo +nightly expand` command to get all macro expansions (I also like `cargo doc` for viewing all the APIs), see code comments for explanations:

```rust
// We set the allocator to a custom allocator for Postgres, we'll cover this later...
#[global_allocator]
static GLOBAL: pg_extend::pg_alloc::PgAllocator = pg_extend::pg_alloc::PgAllocator;

// The magic function Postgres looks for on load of the module, without this Postgres will reject
//    the library. `no_mangle` makes sure that the symbol name is not munged, `link_name` forces
//    the binding name, It's probably not necessary.
#[no_mangle]
#[allow(non_snake_case)]
#[allow(unused)]
#[link_name = "Pg_magic_func"]
pub extern "C" fn Pg_magic_func() -> &'static pg_extend::pg_sys::Pg_magic_struct {
    use pg_extend::{pg_sys, register_panic_handler};
    use std::mem::size_of;
    use std::os::raw::c_int;

    // This defines what configuration the extension was built with, the interface for the `Pg_magic_func`
    //    returns a reference to this const, to match that which postgres requires.
    const my_magic: pg_extend::pg_sys::Pg_magic_struct = pg_sys::Pg_magic_struct {
        len: size_of::<pg_sys::Pg_magic_struct>() as c_int,
        version: pg_sys::PG_VERSION_NUM as std::os::raw::c_int / 100,
        // The rest of this options all come from compile time parameters in the Postgres build.
        funcmaxargs: pg_sys::FUNC_MAX_ARGS as c_int,
        indexmaxkeys: pg_sys::INDEX_MAX_KEYS as c_int,
        namedatalen: pg_sys::NAMEDATALEN as c_int,
        float4byval: pg_sys::USE_FLOAT4_BYVAL as c_int,
        float8byval: pg_sys::USE_FLOAT8_BYVAL as c_int,
    };

    // As this is the entry point for the library loading, we use this as an opportunity
    //    to register a panic handler, so that we can control errors being reported back
    //    from Rust to C (Postgres). More on this later.
    register_panic_handler();

    &my_magic
}
```

The `pg_magic` macro can only be used once in a library. This will become clear with the `register_panic_handler` which should only be called once (though I don't think it should matter if it happens more than that), and `#[global_allocator]` can only exist once in a library. I believe this implementation is correct, but if people have opinions on a better way to do this, please reach out.

Now that we have that, the library is marked as a Postgres extension that can be loaded dynamically.

## Unwrapping pg_extern

The pg_extern attribute macro is where all the fun is. There are a number of things it does, and feel free to look at it's [implementation](https://github.com/bluejekyll/pg-extend-rs/blob/f3e5620a43d325b413a9d0c069bcc99b12505e1d/pg-extern-attr/src/lib.rs#L211). I built this after looking at a lot of documentation, some examples I found online, and the experience I had building this other procedural macro, [enum-as-inner](https://crates.io/crates/enum-as-inner). It's not the most straight forward process, but given Rust's type safety, it's generally clear *why* it's wrong, if not *how* to fix it (also `cargo +nightly expand` is a godsend here). I'm not going to walk through the macro implementation here, but rather what it produces (again, see the code comments inline):

```rust
// Again, an unmangled name
#[no_mangle]
pub extern "C" fn pg_add_one(
    // This is the parameter as defined in Postgres,
    //    it actually is a type alias to `*mut FunctionCallInfoData`.
    //    it's mutable, because we can use it for returning data from
    //    the function (though this isn't supported by the library yet)
    func_call_info: pg_extend::pg_sys::FunctionCallInfo,
    // The return is a `Datum` type which is actually a type alias to `usize`,
    //    though we keep this hidden in the library.
) -> pg_extend::pg_sys::Datum {
    use std::panic;

    // Here we unsafely get a mutable reference to the `FunctionCallInfoData`,
    //    again the type is actually `*mut FunctionCallInfoData`. After this point
    //    the borrow checker will start guaranteeing that we're not doing anything
    //    untoward with the data.
    let func_info: &mut pg_extend::pg_sys::FunctionCallInfoData = unsafe {
        func_call_info
            .as_mut()
            .expect("func_call_info was unexpectedly NULL")
    };

    // We're going to put as much as we can into the catch_unwind block, this
    //    will allow us to handle the panic, and perform any cleanup with the
    //    Postgres data that we need to
    let panic_result = panic::catch_unwind(|| {
        // This extracts references to the arguments that were passed into the function.
        let (args, args_null) = pg_extend::get_args(func_info);

        // In this specific example, there is one parameter. It is converted from the
        //    Datum representation via a conversion defined in the `pg_extend::pg_datum`
        //    module.
        let arg_0: i32 = pg_extend::pg_datum::TryFromPgDatum::try_from(
            pg_extend::pg_datum::PgDatum::from_raw(args[0usize], args_null[0usize]),
        )
        // it's safe for us to panic, as there is a panic handler registered.
        //    (this message can be far better, and will be).
        .expect("unsupported function argument type for arg_0");

        // Here is the actual function call! We capture it's result.
        let result = add_one(arg_0);

        // Now we convert the result into a PgDatum, which is our bridge type between this
        //    library, Rust types, and the `pg_extend::pg_sys` types.
        pg_extend::pg_datum::PgDatum::from(result)
    });

    // Here we inspect the panic result
    match panic_result {
        Ok(result) => {
            // if it's ok, and is_null, then we express that through the `&mut` reference to
            //    FunctionCallInfoData.
            func_info.isnull = result.is_null();

            // The PgDatum type has a conversion into the Postgres Datum type. We're outside the
            //    the catch_unwind block, so it's important this next call never panics, it's
            //    a direct conversion to Datum in `PgDatum::into_datum` so this should be true.
            result.into_datum()
        }
        Err(err) => {
            // In an error case, we're just expressing that there is no data to return.
            //    In the future there may be more things we identify that should be cleaned up.
            func_info.isnull = true;

            // Now continue the panic handling.
            panic::resume_unwind(err)
        }
    }
}
```

The above code tries to do as little as possible inside the macro generated code. This is by design, as it's harder to write meta-code than it is to write *actual* code. Also, more shared library code should help with optimization and code size. I like that so little `unsafe` code was necessary, but I'm guessing there will be a lot more as we try to implement all the Datum type conversions. All the supported Datum conversions will be available in the `pg_extend::pg_datum` [module](https://github.com/bluejekyll/pg-extend-rs/blob/f3e5620a43d325b413a9d0c069bcc99b12505e1d/pg-extend/src/pg_datum.rs#L53) (I should note, at the time of this writing there is only a conversion for `i32` to and from `Datum`, not very useful yet).

There is also a function which declares the calling convention ABI this function supports:

```rust
#[no_mangle]
pub extern "C" fn pg_finfo_pg_add_one() -> &'static pg_extend::pg_sys::Pg_finfo_record {
    const my_finfo: pg_extend::pg_sys::Pg_finfo_record =
        pg_extend::pg_sys::Pg_finfo_record { api_version: 1 };
    &my_finfo
}
```

Which is fairly straight forward.

By-the-way, this is the first time I've worked with panic handling in Rust, so please reach out if you see anything that looks wrong with the way I've written this. Tonight, I was even informed of a new library for trying to enforce no panics, named [no_panic](https://crates.io/crates/no-panic). As I mentioned above that we'd get to the panic handler, so let's look at that.

### Errors and Panic handling

The `register_panic_handler` function is responsible for taking all panics from Rust, and properly (I think) converting them into errors reported to Postgres.

```rust
/// This will replace the current panic_handler
pub fn register_panic_handler() {
    use std::panic;
    use crate::pg_error;

    // set (and replace the existing) panic handler, this will tell Postgres that the call failed
    //   a level of Fatal will force the DB connection to be killed.
    panic::set_hook(Box::new(|info| {
        let level = pg_error::Level::Fatal;

        pg_error::log(level, file!(), line!(), module_path!(), format!("panic in Rust extension: {}", info));
    }));
}
```

The `Fatal` error type has a side-effect of failing any running transaction, and closing the connection to the DB. In my testing, if we panicked without a handler, it would cause Postgres to kill the entire DB process, restart and recover. This would be undesirable to say the least, thus the panic handler. Let's look at `pg_error::log` function, because it was really annoying:

### How to easily lose 3 days of development time

Everything in building this library was fairly straightforward up to this point, and just worked. Which was a great feeling. Then while trying to call the log routines in Postgres, I nearly gave up. It was the first case where I was attempting to call Postgres APIs from the Rust, rather than the other direction, and I couldn't get it to link, here's the code:

```rust
// The log method implicitly needs to allocate a C style string. I'm not super happy with this
//    interface as it doesn't allow a caller to just pass in a `Cstr` directly, so this will
//    change in the future. Also, `file` and `func_name` will be `&'static str` in almost all
//    cases, so we'll probably change this back to that.
pub fn log<T1, T2, T3>(level: Level, file: T1, line: u32, func_name: T2, msg: T3)
where
    T1: Into<Vec<u8>>,
    T2: Into<Vec<u8>>,
    T3: Into<Vec<u8>>,
{
    use std::ffi::CString;

    // convert to C ffi, we need to allocate on conversion from Rust strings to C strings, due to
    //    the fact that they are stored differently. i.e. Rust stores the length of the string,
    //    whereas C is null terminated.
    let file = CString::new(file.into()).expect("this should not fail: file");
    let line = line as c_int;
    let func_name = CString::new(func_name.into()).expect("this should not fail: func_name");
    let msg = CString::new(msg.into()).expect("this should not fail: msg");

    // now we perform the conversions as required by the FFI interfaces.
    let file: *const c_char = file.as_ptr();
    let func_name: *const c_char = func_name.as_ptr();
    let msg: *const c_char = msg.as_ptr();

    let errlevel: c_int = c_int::from(level);

    // log the data:
    unsafe {
        // I don't know the reasoning behind these interfaces in Postgres, but I was able to unwrap
        //    these from the standard `ereport` macro in the Postgres headers. `errstart`, `errmsg`,
        //    and `errfinish` are calls into Postgres from this library.
        if pg_sys::errstart(errlevel, file, line, func_name, ERR_DOMAIN.as_ptr() as *const c_char) {
            let msg_result = pg_sys::errmsg(msg);
            pg_sys::errfinish(msg_result);
        }
    }
}
```

This all works *now*, but it took me a while to get it to build. The reason was `Undefined symbols for architecture x86_64`! I tried everything to get this to link. I tried linking against every `dylib` (I'm on macOS) and `.a` in the `brew` installed version of Postgres, searched them all with `nm`. Then I built Postgres from scratch and scoured every built artifact again with `nm` to find the what I should link against, statically or dynamically, for those symbols. I almost gave up, but then came across this [answer](https://stackoverflow.com/questions/41456777/how-to-build-a-postgres-extension-using-cgo) on stackoverflow for building postgres extensions with `cgo`. And then I spent a bunch of time trying to figure out how pass similar flags to the Rust compiler, and here's the answer:

```console
$> RUSTFLAGS="-C link-arg=-undefineddynamic_lookup" cargo build
   Compiling pg-extend v0.2.0 (${PATH_TO_LIBRARY}/pg-extend-rs/pg-extend)
   Compiling add-one v0.1.0 (${PATH_TO_LIBRARY}/pg-extend-rs/examples/add_one)
   Finished release [optimized + debuginfo] target(s) in 8.89s
```

The relief of something finally building after beating your head against that virtual wall behind the computer screen is the greatest of gifts. It let's you finally sleep and stop considering all the possible things you haven't tried yet to fix the problem.

From the docs, here's what that argument does to `ld` in the `llvm` tools: `Specifies how undefined symbols are to be treated. Options are: error, warning, suppress, or dynamic_lookup.  The default is error.`

Now, one last thing, the allocators.

## Properly allocating memory in Postgres

Postgres has it's own allocator, `palloc`, as well as an associated `pfree`. All memory allocated with `palloc` is guaranteed to be deallocated when a transaction and/or connection are closed. This is a nice feature for not leaking memory. Somewhat recently, Rust stabilized overriding the global allocator. This was the line in the `pg_magic` macro that was annotated with `#[global_allocator]`. The allocator implementation is straight forward, but I have some open questions about whether or not it's correct, here it is:

```rust
pub struct PgAllocator;

unsafe impl GlobalAlloc for PgAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // TODO: is there anything we need ot do in terms of layout, etc?
        pg_sys::palloc(layout.size()) as *mut u8
    }

    unsafe fn dealloc(&self, ptr: *mut u8, _layout: Layout) {
        pg_sys::pfree(ptr as *mut c_void)
    }
}
```

It's pretty simple (also requires the `RUSTFLAG` linker setting), it just calls into the Postgres allocator. You'll notice the `TODO` there as I'm unclear what to do about alignment or other layout issues.

## Load the extension in Posrgres

Connect to the DB and load the function (your DB connection probably differs):

```console
$> psql postgres
psql (11.1)
Type "help" for help.

postgres=# CREATE FUNCTION add_one(integer) RETURNS integer AS '${PATH_TO_LIBRARY}/pg-extend-rs/target/release/libadd_one.dylib', 'pg_add_one' LANGUAGE C STRICT;
CREATE FUNCTION
postgres=# SELECT add_one(3);
 add_one
---------
       4
(1 row)

postgres=# \q
```

Notice that the symbol to load is `pg_add_one` and not `add_one`, as the latter would have conflicted with the original function in Rust. As a future task, I want to build generators for the psql scripts to load the function

## Just the beginning

This is really just the beginning of this library. There is going to be a long road to complete it, as there are a lot of type conversions to implement for the `PgDatum` type. As I have time, I will get to it, but if you find this useful and want to contribute, please feel welcome. I've picked as open a set of licenses as possible to allow people from all walks to get in on the fun, [bluejekyll/pg-extend-rs](https://github.com/bluejekyll/pg-extend-rs).

As always, thank you to all the Rust contributors who continue to make the language an absolute pleasure.