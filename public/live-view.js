var url = new URL(location.href);
url.protocol = url.protocol.replace('http', 'ws');
url.pathname = '/live-view';
var live_view = new WebSocket(url);
live_view.addEventListener('open', event => {
  console.log('open', event);
  document.querySelectorAll('[data-live-view]')
    .forEach(view => {
      live_view.send(JSON.stringify({
        subscribe: view.getAttribute('data-live-view'),
      }))
    });
});

live_view.addEventListener('message', ({ data }) => {
  var { id, render } = JSON.parse(data);

  document.querySelectorAll(`[data-live-view="${id}"]`)
    .forEach(view => {
      view.innerHTML = render;
    });
});

live_view.addEventListener('close', event => {
  console.log('close', event);
});

document.addEventListener('click', event => {
  var event_name = event.target.getAttribute('live-click');

  if(event_name) {
    live_view.send(JSON.stringify({
      event: event_name,
    }));
  }
});
