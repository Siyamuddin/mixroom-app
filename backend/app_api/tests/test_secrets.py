import base64
import importlib
import json
import unittest
from unittest import mock

import support  # noqa: F401

module = importlib.import_module("src.common.secrets")


class SecretsTests(unittest.TestCase):
    def test_load_apple_root_certificates_decodes_pem_to_der(self):
        der = b"fake-der-certificate"
        body = base64.b64encode(der).decode("ascii")
        pem = f"-----BEGIN CERTIFICATE-----\n{body}\n-----END CERTIFICATE-----\n"

        with mock.patch.object(module.config, "APPLE_ROOT_CA_SECRET_ARN", "secret"), mock.patch.object(
            module,
            "get_secret_string",
            return_value=json.dumps({"pem_bundle": pem}),
        ):
            result = module.load_apple_root_certificates()

        self.assertEqual(result, [der])

    def test_load_apple_root_certificates_accepts_base64_der_list(self):
        der = b"fake-der-certificate"

        with mock.patch.object(module.config, "APPLE_ROOT_CA_SECRET_ARN", "secret"), mock.patch.object(
            module,
            "get_secret_string",
            return_value=json.dumps(
                {"certificates_der_base64": [base64.b64encode(der).decode("ascii")]}
            ),
        ):
            result = module.load_apple_root_certificates()

        self.assertEqual(result, [der])


if __name__ == "__main__":
    unittest.main()
