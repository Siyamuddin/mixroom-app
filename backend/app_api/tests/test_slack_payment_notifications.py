import importlib
import json
import unittest
from unittest import mock

import support  # noqa: F401

module = importlib.import_module("src.handlers.slack_payment_notifications")


class _Response:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return b"ok"


class SlackPaymentNotificationTests(unittest.TestCase):
    def test_formats_toss_payment_as_major_currency_units(self):
        payload = module._build_slack_payload(
            {
                "provider": "toss",
                "plan_code": "producer",
                "product_code": "producer_monthly",
                "customer_email": "producer@example.com",
                "amount": 12900,
                "currency": "KRW",
                "region_code": "KR",
                "purchased_at": "2026-09-02T12:00:00+00:00",
                "event_id": "toss:payment-1",
            }
        )

        self.assertEqual(
            payload["text"],
            "New subscription payment: Toss Payments · Producer · KRW 12,900",
        )
        fields = payload["blocks"][1]["fields"]
        self.assertIn("KR", fields[2]["text"])
        self.assertIn("producer@example.com", fields[5]["text"])

    def test_formats_paddle_lowest_currency_units(self):
        payload = module._build_slack_payload(
            {
                "provider": "paddle",
                "plan_code": "studio",
                "amount": "1999",
                "currency": "USD",
            }
        )

        self.assertIn("USD 19.99", payload["text"])

    def test_handler_posts_each_sns_payment_event(self):
        event = {
            "Records": [
                {
                    "Sns": {
                        "Message": json.dumps(
                            {
                                "detail-type": "billing.purchase_completed",
                                "detail": {
                                    "provider": "apple",
                                    "plan_code": "starter",
                                    "user_id": "user-1",
                                    "event_id": "apple:event-1",
                                },
                            }
                        )
                    }
                }
            ]
        }

        billing_event = {
            "event_type": "apple_webhook",
            "raw_payload": {"notificationType": "SUBSCRIBED"},
        }
        with (
            mock.patch.object(module, "_billing_event", return_value=billing_event),
            mock.patch.object(module, "_enrich_purchase", side_effect=lambda detail, _record: detail),
            mock.patch.object(module, "_post_to_slack") as post,
        ):
            result = module.handler(event, None)

        self.assertEqual(result, {"statusCode": 200, "notified": 1, "ignored": 0})
        self.assertIn("Apple App Store", post.call_args.args[0]["text"])

    def test_handler_ignores_renewals_and_cancellations(self):
        event = {
            "Records": [
                {
                    "Sns": {
                        "Message": json.dumps(
                            {"detail": {"event_id": "apple:renewal", "provider": "apple"}}
                        )
                    }
                },
                {
                    "Sns": {
                        "Message": json.dumps(
                            {"detail": {"event_id": "google:renewal", "provider": "google"}}
                        )
                    }
                },
                {
                    "Sns": {
                        "Message": json.dumps(
                            {"detail": {"event_id": "paddle:renewal", "provider": "paddle"}}
                        )
                    }
                },
            ]
        }
        billing_events = {
            "apple:renewal": {
                "event_type": "apple_webhook",
                "raw_payload": {"notificationType": "DID_RENEW"},
            },
            "google:renewal": {
                "event_type": "google_rtdn",
                "raw_payload": {"subscriptionNotification": {"notificationType": 2}},
            },
            "paddle:renewal": {
                "event_type": "transaction.completed",
                "raw_payload": {
                    "data": {"origin": "subscription_recurring", "subscription_id": "sub_1"}
                },
            },
        }

        with (
            mock.patch.object(
                module,
                "_billing_event",
                side_effect=lambda event_id: billing_events[event_id],
            ),
            mock.patch.object(module, "_post_to_slack") as post,
        ):
            result = module.handler(event, None)

        self.assertEqual(result, {"statusCode": 200, "notified": 0, "ignored": 3})
        post.assert_not_called()

    def test_initial_purchase_classification(self):
        cases = (
            ({"event_type": "toss_payment_confirmed", "raw_payload": {}}, True),
            ({"event_type": "toss_billing_payment_approved", "raw_payload": {}}, True),
            (
                {
                    "event_type": "apple_webhook",
                    "raw_payload": {"notificationType": "SUBSCRIBED"},
                },
                True,
            ),
            (
                {
                    "event_type": "google_rtdn",
                    "raw_payload": {"subscriptionNotification": {"notificationType": 4}},
                },
                True,
            ),
            (
                {
                    "event_type": "transaction.completed",
                    "raw_payload": {"data": {"origin": "web", "subscription_id": "sub_1"}},
                },
                True,
            ),
        )
        for record, expected in cases:
            with self.subTest(record=record):
                self.assertEqual(module._is_initial_subscription_purchase(record), expected)

    def test_post_rejects_non_slack_webhook(self):
        with mock.patch.object(module, "_slack_webhook_url", return_value="https://example.com/hook"):
            with self.assertRaisesRegex(ValueError, "invalid"):
                module._post_to_slack({"text": "test"})

    def test_post_sends_json_to_slack(self):
        with (
            mock.patch.object(
                module,
                "_slack_webhook_url",
                return_value="https://hooks.slack.com/services/T/B/token",
            ),
            mock.patch.object(module.request, "urlopen", return_value=_Response()) as urlopen,
        ):
            module._post_to_slack({"text": "payment"})

        sent_request = urlopen.call_args.args[0]
        self.assertEqual(json.loads(sent_request.data), {"text": "payment"})
        self.assertEqual(urlopen.call_args.kwargs["timeout"], 10)

    def test_webhook_url_loads_encrypted_parameter_once(self):
        original_url = module._webhook_url
        module._webhook_url = None
        self.addCleanup(setattr, module, "_webhook_url", original_url)

        with (
            mock.patch.dict(
                module.os.environ,
                {"SLACK_PAYMENT_WEBHOOK_PARAMETER_NAME": "/mixroom/prod/slack/payment-webhook"},
            ),
            mock.patch.object(
                module._ssm_client,
                "get_parameter",
                return_value={"Parameter": {"Value": "https://hooks.slack.com/services/T/B/token"}},
            ) as get_parameter,
        ):
            first = module._slack_webhook_url()
            second = module._slack_webhook_url()

        self.assertEqual(first, second)
        get_parameter.assert_called_once_with(
            Name="/mixroom/prod/slack/payment-webhook",
            WithDecryption=True,
        )


if __name__ == "__main__":
    unittest.main()
