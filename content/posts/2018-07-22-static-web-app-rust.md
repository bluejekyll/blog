+++
title = "A static web app in Rust"
date = 2018-07-22
description = "A three day tour of Yew and WASM with Rust"
aliases = ["/rust/2018/07/22/static-web-app-rust.html"]

[taxonomies]
topics=["programming", "rust"]
+++

I am not a frontend engineer. I don't generally have the patience for figuring out how to make something look the way I want; on top of that, all web work basically requires a knowledge of Javascript. I have no qualms in saying that I don't enjoy writing Javascript. This has basically kept me out of the web frontend space, even on hobby projects. But now I can target the web with my favorite language, Rust and deliver WASM. This post is about a minor little adventure in learning some of the tools for doing this.

# Kitchen Patrol

My family gets together in the summer at a cabin in the middle of nowhere. There are a lot of us, and each day has a set of work that needs to be done for everything to come together and no individuals being overtaxed with the effort. My sister-inlaw, being expert in organization, years ago devised a chore chart for all the work. Everyone gets assigned a job, somewhat indiscriminately (though age is a requirement for some jobs), the main goal being that no person does two major jobs in a day (like cooking for 24 and also doing all the dishes after the dinner). Filling this out always took time and energy, so this year I told her, "hey why don't we build something for it?". So with her acting as the project manager and me the engineer, it was time to write an application to take care of this. Now I get to share that experience, and don't judge too harshly, my web UI skills are basically non-existent.

I got my inspiration from this much more detailed and impressive post, [A web application completely in Rust](https://medium.com/@saschagrunert/a-web-application-completely-in-rust-6f6bdb6c4471). So if you want to really learn this, you should read that, not this. After reading that I realized now is a good time for me to try this. Every year, I decide to take a stab at some frontend development, mainly to keep up with the changing ecosystem. After reading the linked to article, it made it clear we would now be able to do something decent in Rust with minimal, even no, Javascript, awesome.

## Design

I had a few goals:

- only use Rust for code (except CSS and initial `index.html`)
- target WASM, because this is the future ;)
- learn Yew, and see what it's like (build up components from scratch)
- build it as a static site (no backend, learn/use `LocalStorage`)
- build it as a single-page-app, it's literally one page

Here's what the chart itself will end up generating (all names are fake):

![Chore Chart](chart.png)

Initially this was a static page. I implemented it with a statically generated list of people and jobs (the jobs and number of days are still static). I decided the first thing we'd make dynamic would be the list of people associated to the jobs, for that we'd need another form that will look like this:

![Edit People](edit-people.png)

As I'm no expert in the area, I decided not to fret too much if I couldn't get things to look right, again, if you're going to be bothered with fonts or look, you want to go elsewhere. Just for reference, the look/feel I was going for was a legal pad with a marker.

## Getting started

This all builds off the excellent work done on `stdweb` and `cargo-web`. For this we won't be using `stdweb` directly, though it is necessary for a component which uses `<select/>`, but instead the `Yew` framework. I went with this directory structure (mostly standard):

```text
docs/      # contains the static site for Github pages
src/       # the Rust source code
src/data/  # non-web specific components (there's a simple CLI)
src/web/   # all web components
static/    # static content to be included with the app
static/index.html  # starting point for the App (very simple)
static/styles.css  # our stylesheet
Cargo.toml # Rust configs
Web.toml   # cargo-web configuration
```

For all the web components I put them into `src/web` and only compile that when the (default) feature `web-spa` is enabled. If I was going to build a "prod" application, I'd probably have this `src/web` be a separate crate all together.

Let's get the environment ready:

```console
$> cargo install cargo-web
```

Woh, that's it! That will also install `wasm32-unknown-unknown` toolchain into your `rustup` env. Btw, you'll be needing the nightly `rustc`, so switch to that (also, I had a problem with compiling some of the tools on the most recent Rust version, so I needed to use `nightly-2018-07-17`):

```console
$> rustup default nightly-2018-07-17
```

For our dependencies in `Cargo.toml` it isn't much:

```toml
[dependencies]
serde = "1.0"
serde_derive = "1.0"
serde_json = "1.0"
stdweb = "0.4"
yew = "0.4"
```

And now we're ready to write some code.

## Components

Some of this stuff is documented well, other parts less so. To generate the docs, I needed to use the stable compiler, as there were some issues with nightly, but it's definitely worth generating those:

```console
$> cargo +stable doc --open
```

I have spent a little time familiarizing myself with `Vue` and `React` (only so far as tutorials and play apps in the past). I found the `Yew` framework to be very reminiscent of `React`, it claims to be ["inspired by Elm and ReactJS"](https://github.com/DenisKolodin/yew) (I've never worked with `Elm`).

There are two traits `Component` and `Renderable`. `Component` implements all of the functions around creating and updating the component. `Renderable` implements the functions for rendering the component, `view`. It's not yet clear to me why these two are separate traits and not just one, there's possibly a good reason, but it's not obvious to me yet. `Component` has three functions, `create`, `update`, and `change`; `change` is only required if your component carries a custom set of properties, this requirement is enforced at runtime (errors get spewed to the javascript console).

Let's look at our simplest component for the Chart. First the types:

```rust
#[derive(Clone)]
pub struct Chart {
    // this is a version marker we're using for determing when to reload data
    people_version: usize,
    // the actual chart data, for display
    week: Week,
}

/// The chart properties, it just let's us know what version of the data we need
#[derive(Clone, Default, PartialEq)]
pub struct ChartProps {
    pub people_version: usize,
}
```

Now the implementation of the chart's calculate function that will create the data for the chart: 

```rust
impl Chart {
    /// Our calculate function will construct a new week for the chart
    fn calculate(context: &mut Context) -> Self {
        context.console.debug("calculating new week");
        // jobs are static
        let jobs = kp_chart::default_jobs();

        // We'll come back to this, it's restoring the set of people from the
        //  local store
        let (people_version, people) = PeopleStore::restore(&mut *context)
            .map(|p| (p.inc, p.people))
            .unwrap_or_else(|| (0, kp_chart::default_people()));
        Self {
            people_version: people_version,
            // we're calculating 5 days worth of jobs
            week: kp_chart::calculate(5, jobs, people),
        }
    }
}
```

And then here is the component implementation, which is pretty simple:

```rust
impl Component<Context> for Chart {
    type Message = ();
    type Properties = ChartProps;

    // Initial state of the component, we're ignoring the props
    //   because the storage version will always be loaded here.
    fn create(_props: Self::Properties, context: &mut Env<Context, Self>) -> Self {
        context.console.debug("creating Chart");
        Self::calculate(&mut *context)
    }

    // we don't accept any messages.
    fn update(&mut self, _msg: Self::Message, _context: &mut Env<Context, Self>) -> ShouldRender {
        true
    }

    // for changes, we're going to update our chore chart if the version is different from the one we already have.
    fn change(
        &mut self,
        props: Self::Properties,
        context: &mut Env<Context, Self>,
    ) -> ShouldRender {
        if self.people_version != props.people_version {
            context.console.debug("updating Chart");
            *self = Self::calculate(&mut *context);
            true
        } else {
            false
        }
    }
}
```

In the above we're not actually doing a lot. The actual logic for the [calculation](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/lib.rs#L69) is not complex (and needs to be better). It currently rotates through all the people and jobs, selecting between adults, teens, and children for each job. I'm hoping that the `Yew` console logging will eventually be integrated into the Rust logger that most people use, but it's easy enough to use.

The `view` function is here for rendering:

```rust
impl Renderable<Context, Chart> for Chart {
    fn view(&self) -> Html<Context, Self> {
        let header = |name: &str| {
            html!{
                <th>{ format!("{}", name) }</th>
            }
        };
        let people_cell = |people: &[Person]| {
            let mut people_str = String::new();
            for person in people {
                people_str.push_str(person.name());
                people_str.push_str(", ");
            }

            html!{
                <td>{ people_str }</td>
            }
        };
        let job_row = |(job_idx, job): (usize, &Job)| {
            let days = self.week.days();
            html!{
                <tr>{ header(job.name()) } { for days.iter().map(|d| people_cell(d.get_job_people(job_idx))) }</tr>
            }
        };

        html! {
            <>
                <h2>{"Job Chart"}</h2>
                <table>
                    <thead>
                        <tr><th>{"Job"}</th> { for self.week.days().iter().map(|d| header(d.name())) }</tr>
                    </thead>
                    <tbody>
                        { for self.week.jobs().enumerate().map(|j| job_row(j)) }
                    </tbody>
                </table>
            </>
        }
    }
}
```

The above showcases the pretty amazing `html!` macro that gives us something very much like JSX. It's quite impressive in how it works, but has some interesting quirks. For example, notice the `for ...` construction. As I understand this, you need to something that is `IntoIterator<Item=yew::html::Html>`, this is why we call out to another function for the actual `header(...)` and `job_row(...)` rendering. It's really quite an amazing macro.

This component is used in the [`RootModel`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/root.rs), which is the top-level component. Let's look at it's usage:

```rust
impl Renderable<Context, RootModel> for RootModel {
    fn view(&self) -> Html<Context, Self> {
        use web::Chart;

        html! {
            <div>
                <h1>{"Kitchen Patrol Charts"}</h1>
                // This is the binding for the Chart model:
                <Chart: people_version={self.people_version},/>
                // Continue reading for discussion the PeopleModel...
                <PeopleModel: on_save=|inc| RootMsg::PeopleUpdated(inc),/>
            <div/>
        }
    }
}
```

You see in the above snippet, `people_version={self.people_version}` is the property that is bound to our properties type, [`ChartProps::people_version`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/chart.rs#L16), which is very elegant, and vaguely like the React system, except that it's type-safe and validated at compile time! Honestly, this is my excitement for Rust in this context. We can have the elegance of HTML templates that live alongside the component implementation, and with `cargo web start` we even get a similar development experience to Javascript of the immediately updated experience during development. It's extremely hard to express my excitement here, as to me, Javascript is a hostile development environment, with many issues only discoverable at runtime. That is juxtaposed to this experience of compile time guarantees creating a sense of security so long lacking in web development.

Now for a bit more complexity, you'll notice in the previous example this property:

```rust
<PeopleModel: on_save=|inc| RootMsg::PeopleUpdated(inc),/>
```

## Messaging events between components

This introduces some message passing. The [`RootMsg::PeopleUpdated(inc)`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/root.rs#L10) enum type will be passed back to our `RootModel` on the (custom) `on_save` event. This is ultimately tied into an `onclick` DOM event binding to a save `<button/>` in the [`PeopleModel`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/people.rs#L219):

```rust
html! {
    //...
    <button onclick=|_| PeopleMsg::SavePeople, >
        <i class=("fa", "fa-floppy-o"), aria-hidden="true",></i>
    </button>
    //...
}
```

That on event calls through the [`PeopleMsg::SavePeople`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/people.rs#L16) message type, which is processed in the [`PeopleModel::update`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/people.rs#L109) function:

```rust
match msg {
    PeopleMsg::SavePeople => {
        context.console.debug("saving PeopleModel");
        let mut people: PeopleStore = self.clone().into();
        people.store(&mut *context);
        *self = PeopleModel::from(people, self.on_save.take());

        self.on_save.as_ref().map(|e| e.emit(self.inc));
        true
    }
    _ => (),
}
```

This emits the event to the upstream `RootModel` via `PeopleModel::on_save` callback that was registered through the properties passed in on the `RootModel`s creation of the `PeopleModel` via the `RootModel::view` method. Of course when the people model is saved, it needs to write it somewhere. `Yew` makes all of this very simple and easy. Of course, when you save something, it generally should be preserved somewhere and for this I had decided to only use LocalStorage in the browser, of course this means there are no backups and the data is tied to the access location, but still very cool. To use this, we just need to add the service to our [`Context`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/mod.rs#L4-L7) type:

```rust
pub struct Context {
    pub console: ConsoleService,
    pub local_store: StorageService,
}
```

The storage service is registered as [`Area::Local`](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/main.rs#L31):

```rust
let context = Context {
    console: ConsoleService::new(),
    local_store: StorageService::new(Area::Local),
};
```

And this is easily [updated and used](https://github.com/bluejekyll/kp-chart/blob/caae42093e187bbbd0aab71ec7879c222e173339/src/web/people.rs#L42-L61) as [String]'s (json in this case).

All of this was really fun to do; thank you to [Denis Kolodin](`https://github.com/DenisKolodin`) for [Yew](https://github.com/DenisKolodin/yew), it was a pleasure to learn and use. And now, you can use the ugly static app here: [https://bluejekyll.github.io/kp-chart/](https://bluejekyll.github.io/kp-chart/). The only thing server side is the loading of the static files: `index.html`, `kp-chart.js` (binding javascript for the WASM), `kp-chart.wasm`, and `styles.css`. After that everything is 100% on the client. When you save it will preserve to `LocalStorage` in your browser. I've tested this on iOS Safari, macOS Safari, Firefox, and Chrome. It all seems to work perfectly. What's also really cool, is there is no server side required at all, once compiled the files can be loaded directly from the filesystem and run as an SPA, which is really cool (at least on Firefox).

Here are links to all the components I implemented for this, i.e. nothing off the shelf:

- [RootModel](https://github.com/bluejekyll/kp-chart/blob/master/src/web/root.rs#L5-L52) - starting point for the application
- [Chart](https://github.com/bluejekyll/kp-chart/blob/master/src/web/chart.rs#L9-L103) - chart/table of the rendered jobs and people
- [PeopleModel](https://github.com/bluejekyll/kp-chart/blob/master/src/web/people.rs#L74-L229) - people edit form
- [PeopleStore](https://github.com/bluejekyll/kp-chart/blob/master/src/web/people.rs#L36-L72) - storage object that reads and writes itself to LocalStorage (not a component)
- [EditDelete](https://github.com/bluejekyll/kp-chart/blob/master/src/web/people.rs#L269-L335) - Edit and Delete component for changing and removing people
- [PersonName](https://github.com/bluejekyll/kp-chart/blob/master/src/web/people.rs#L338-L408) - Person name field for displaying and editing a person's name
- [PersonAbility](https://github.com/bluejekyll/kp-chart/blob/master/src/web/people.rs#L411-L500) - Person ability, aka age, field for displaying and editing a person's age

Pretty cool stuff I think, and none of it seems more complex than React. In point of fact, I think it's simpler because the compiler tells you when you've made any mistakes in your code.

## Fearless web development

Rust already taught to be fearless in regards to systems programming while working on [TRust-DNS](https://github.com/bluejekyll/trust-dns/), now it's showing me that I can be fearless when working with frontend web design. While this little web-app wasn't much, it shows me that Rust is going to be amazing in this space, especially for those of us that enjoy the hand-holding of `rustc`.

All the code for this can be found here: [kp-chart](https://github.com/bluejekyll/kp-chart)

*some gotchas*:

- multiple classes on a type:

I wanted to write `<i class="fa fa-trash fa-fw", aria-hidden="true" />`, but instead we must write `<i class=("fa", "fa-trash", "fa-fw"), aria-hidden="true", />`. I just assume this is some limitation in the `html!` macro parser.

- property lists must be comma `,` separated and terminated:

For example instead of `<button class="button" onclick=|_| PeopleMsg::AddPerson >` you must write `<button class="button", onclick=|_| PeopleMsg::AddPerson, >`. This is true for standard HTML elements and custom components.

- raw character data must escaped:

You can't write `<p>Random string</p>` you must write `<p>{"Random string"}</p>`

- `html!` macro arguments must have a single wrapping element

For this it can be either the element you're using, or the handy empty element `<></>`

Thanks!
