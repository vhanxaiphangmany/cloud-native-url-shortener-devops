from app.main import REQUEST_LATENCY, REQUESTS, REDIRECTS


def test_application_metrics_are_registered():
    assert REQUESTS._name == "url_shortener_http_requests"
    assert REQUEST_LATENCY._name == "url_shortener_http_request_duration_seconds"
    assert REDIRECTS._name == "url_shortener_redirects"


def test_request_metrics_accept_labeled_observations():
    REQUESTS.labels("GET", "/health", "200").inc()
    REQUEST_LATENCY.labels("GET", "/health").observe(0.025)

    assert REQUESTS.labels("GET", "/health", "200")._value.get() >= 1
    assert REQUEST_LATENCY.labels("GET", "/health")._sum.get() >= 0.025
