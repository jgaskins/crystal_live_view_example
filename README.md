# crystal_live_view_example

Proof of concept for a Crystal version of [Phoenix Live View](https://dockyard.com/blog/2018/12/12/phoenix-liveview-interactive-real-time-apps-no-need-to-write-javascript)

## Installation

```bash
git clone https://github.com/jgaskins/crystal_live_view_example.git
```

## Usage

```bash
crystal src/live_view_example.cr
```

Then point your browser to http://localhost:8080/

You should see an increasing timestamp and 

## Development

All of the plumbing is in [`src/live_view.cr`](https://github.com/jgaskins/crystal_live_view_example/tree/master/src/live_view.cr) and [`public/live-view.js`](https://github.com/jgaskins/crystal_live_view_example/tree/master/public/live-view.js).

## Contributing

1. Fork it (<https://github.com/jgaskins/crystal_live_view_example/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
