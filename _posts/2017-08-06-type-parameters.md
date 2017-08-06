---
layout: post
title:  "They're not Generics; they're TypeParameters"
date:   2017-08-06 00:00:00 -0700
categories: rust
---

*A story about grokking Generics in Rust*

A while back I was writing some Rust, and the compiler yelled at me, it's such a perfectionist. Luckily it also gave me a very helpful hint about how to fix the problem. I copy-and-pasted the hint into my code (yeah I know, you just lost some respect for me), and promised myself to go back and understand why later. I finally had to write some new code that used these interfaces and so I got to revisit the error message and why it was necessary. Before we get into that argument with the compiler, it might be helpful to walk down memory lane with Generics.

# My brief history with "Generics"

My first introduction to the concept of Generics was with the `C++` Template system in a [Computer Science](https://computerscience.vassar.edu) class in [College](https://www.vassar.edu). It's been a while, but I still have this `typedef` name in my head, `interator`. I had typedeffed it to reduce my typing throughout the code, it was something like:

```c++
typedef std::vector<int>::iterator interator;
```

To this day I frequently mistype iterator as interator... crazy how that stuff can stick with you. Most of my time was spent with Java and it's Generics system, though. It was definitely something initially missing from Java after switching from C++ (they were finally added in 1.5). Some people don't like Generics, let me just say, I am firmly in the camp of Generics being awesome. An example of why Generics are necessary in Java is most obvious with collections like Map, before Generics:

```java
String foo = "foo";
String bar = "bar";

ArrayList vec = new ArrayList(Arrays.asList("abc", "123"));
String str = "123";

Map map = new HashMap();
map.put(foo, vec);
map.put(bar, str);

// we need to cast because map.get() returns Object, not ArrayList
List list = (List)map.get(foo);
// ClassCastException! this is a String, but this map doesn't care!
List not_list = (List)map.get(bar);
```

With Generics we can at least turn that into a compile time error. Compile time errors mean things don't blow up in production, effectively giving you a free unit test:

```java
// A Map of String to an Object which implements List
Map<String, List> map = new HashMap<String, List>();
map.put(foo, vec);
// compiler error! expected List, found String
//  one less runtime bug!
map.put(bar, str);

// If we got here, there would be no need to cast!
List list = map.get(foo);
// the compiler never even got here!
List not_list = map.get(bar);
```

And then I started learning Rust...

# You thought you knew Generics? Welcome to Rust

Rust definitely raises the conceptual bar with it's Generics and type system. To understand why, it's important to understand the difference between monomorphism and polymorphism. Object Oriented languages all support polymorphic functions. In C++ this is opt-in with the `virtual` keyword, and in Java it's opt-out with the `final` keyword. Rust also supports polymorphism with [Trait Objects](https://doc.rust-lang.org/book/first-edition/trait-objects.html), to use it you must cast a reference to a to a trait object, for example:

```rust
let obj = Object::new();
let trait_obj = &obj as &Trait;
```

This makes Rust similar to C++ in the sense that polymorphism is opt-in. The issue with this is that at runtime it's a little bit more expensive. So what do we do to make this less expensive? We get to use monomorphism, and this is where the Generic system in Rust shines. Let's just review quickly polymorphism, shown in Rust:

```rust
trait Animal {
  // default impl, don't most animals have 4 legs?
  fn num_legs(&self) -> usize { 4 }
}

// Define a Dog and implement Animal for it
struct Dog;
impl Animal for Dog {
  // use the default impl
}

// Define a Chicken and implement Animal for it
struct Chicken;
impl Animal for Chicken {
  fn num_legs(&self) -> usize { 2 }
}

fn print_num_legs(animal: &Animal) {
  println!("legs: {}", animal.num_legs());
}

fn main() {
    let dog = Dog;
    let chicken = Chicken;
    
    // Notice the cast to the Trait Object
    print_num_legs(&dog as &Animal);
    print_num_legs(&chicken as &Animal);
}

```

The above `print_num_legs` function is polymorphic, because it operates on the concept of Animal. This is a bit of a contrived example, obviously. An interesting difference between Rust and C++/Java at this point is where the opt-in/opt-out of polymorphism occurs. In Rust it's from the reference to the Animal object, but in C++/Java, it's actually in the definition of the class itself. Initially this struck me as odd, but only because I wasn't used to it. Now of course I find it funny that C++ and Java did it the other way (C++ also requires references to objects for polymorphism, if the variable is stack based, then polymophism will not come into play in the way that it always does in Java). Polymorphism comes at a cost, and that's the fact that when you cast a reference to a Trait Object the compiler must capture additional information behind the pointer to that memory, mainly the virtual function table. This is the table of functions which the object, Dog for example, implement with references to the function actually provided by that instance of the object.

This cost can be removed by using monomorphism, and if your following along, Generics. It should be mentioned that polymorphism comes at the cost of runtime memory, where as monomorphism comes at the cost of additional binary size. There is no free beer here. The logic from above isn't all that different, it all comes in the `print_num_legs` function definition:

```rust
fn print_num_legs<A: Animal>(animal: &A) {
  println!("legs: {}", animal.num_legs());
}

fn main() {
    let dog = Dog;
    let chicken = Chicken;
    
    // Notice no cast is necessary
    print_num_legs(&dog);
    print_num_legs(&chicken);
}
```

This is now a monomorpic call. The compiler literally generates different code for each variation of the call to `print_num_legs`. This reduces our runtime cost, but we get to keep the nice fact that we still only needed to write a single function for all types of Animals.

Ok, now that we're all experts with polymorphism, monomorphism and Generics in Rust, let's dive deeper in to the depths of this type system. Take a look at the interface that tripped me up and took a while to understand, from [here](https://github.com/bluejekyll/trust-dns/blob/a46d1bbe996b69df9dcd964540de57df2d44681e/client/src/client/client.rs#L424):

```rust
pub fn new<CC>(client_connection: CC) -> SecureSyncClientBuilder<CC>
  where CC: ClientConnection,
        <CC as ClientConnection>::MessageStream: Stream<Item=Vec<u8>, Error=io::Error> + 'static
```

OMG, that is a complex signature! Let's break it down, but first a quick review of Generics in Rust:

```rust
// A normal function
fn normal(a: &str) { println!("{:?}", a) } 
```

But what if we want that same function to work with any type? We add a Generic Type Parameter:

```rust
fn generic<T>(a: T) { println!("{:?}", a) }
```

This doesn't compile because we didn't tell Rust that you can print the type T with Debug, let's do that:

```rust
fn generic<T: Debug>(a: T) { println!("{:?}", a) }
```

That's nice and simple. But here's the thing, Generics are just other parameters to the function, TypeParameters. By using the term *parameter*, it helps with understanding more complex use cases. For example, if you want to cast one variable from one type to another you do this:

```rust
// Cast the 32 bit number, 128 to an 8 bit number
fn cast() -> u8 { 128_u32 as u8 }
```

TypeParameters work just the same way! To show what I mean, we need to build up to a more complex example:

```rust
// inline TypeParameter with Trait bound
fn fun_generic<T: Add<T, Output=T>>(a: T, b: T) -> T { a + b }

// equivalent with a where clause
fn fun_generic<T>(a: T, b: T) -> T where T: Add<T, Ouput=T> { a + b }
```

The `Output` parameter of the `Add` trait is an Associated Type, it's defined like this:

```rust
trait Add<RHS = Self> {
    type Output; // associated type
    fn add(self, rhs: RHS) -> Self::Output;
}
```

This allows the return type, `Output` to be declared separately from the `Add` trait. The trait bound for `add` basically says this, `add` can be defined for any type, but it can only be added to itself. This means that `2 /*usize*/ + "3" /*&str*/;` is not legal. It does allow us to change the output though. Let's make up some types, say `BitField8` and `BitField16` types. We'll define `add` on `BitField8` which will append one to another and return a `BitField16`:

```rust
struct BitField8(u8);
struct BitField16(u16);

impl Add<BitField8> for BitField8 {
  type Output = BitField16;
  
  fn add(self, rhs: Self) -> Self::Output {
     let high: u16 = (self.0 as u16) << 8;
     BitField16(high + rhs.0 as u16)
  }
}
```

This isn't very useful, but it shows what is possible with the Generics system in Rust and it's various TypeParameters and AssociatedTypes. This is all very powerful in giving us strong type checking in lots of different cases.

# Now something completely different

Now for why I wrote this post, grokking all of these concepts to fully understand the line that confounded me before. I titled this post, *They're not Generics; they're TypeParameters* because for me just *saying* TypeParameter to myself allowed me to better grasp what is going on in this complex signature: 

```rust
/*1*/ pub fn new<CC>(client_connection: CC) -> SecureSyncClientBuilder<CC>
/*2*/  where CC: ClientConnection,
/*3*/        <CC as ClientConnection>::MessageStream: Stream<Item=Vec<u8>, Error=io::Error> + 'static
```

Let's disect it line-by-line. `CC` is the only direct TypeParameter it's used in both a function parameter and the return type:

```rust
/*1*/ pub fn new<CC>(client_connection: CC) -> SecureSyncClientBuilder<CC>
```

In our where clause we are putting a bound on `CC`, it's a `ClientConnection`, it could have multiple additional bounds, like `Send`. The original code doesn't add `Send`, but let's do it here to make something clearer:

```rust
/*2*/ where CC: ClientConnection + Send,
```

`MessageStream` is an associated type on the `ClientConnection`, like `Output` in `Add`. For various reasons this complexity was needed, it's mainly for TCP and TLS connections where unlike UDP we first have to establish a connection to the remote endpoint, so a generic TypeParameter allows this new function to operate on all three of those connection types.

```rust
/*3*/       <CC as ClientConnection>::MessageStream: Stream<Item=Vec<u8>, Error=io::Error> + 'static
```

Notice something funky here, we are "casting" `CC` to `ClientConnection`, why? Coming from Java with no AssociatedTypes this was very foreign, but it makes sense when you think about what's going on in this statement. `CC` could be either `ClientConnection` or `Send`, so we need to "cast" it to the actual type on which we want to add additional bounds for it's associated type, in this case `MessageStream`. `CC` could be any type of it's bounds, and by "casting" it we are making it clear to the compiler which AssociatedType of which Trait we are referring to.

To finish this off, the MessageStream is then bound to the type `Stream<Item=Vec<u8>, Error=io::Error> + 'static`. This is just saying that MessageStream is a Stream of future data of the type `Vec<u8>`; the raw, binary DNS packet. The additional `'static` bound just specifies that the Stream must either have a `'static` lifetime or be an owned type.

# Grokked

The reason I put this post up is because these concepts were something which confused me for a little bit when getting used to working with Rust. Literally starting to think in terms of TypeParameters has helped clarify some of what is going on when writing generic code. The type system in Rust is so much more advanced than any other language that *I've* used; I'm still getting used to thinking about it in terms that make sense to me. I hope you found it useful.