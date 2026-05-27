import base64
import importlib
import json
import unittest
from unittest import mock

import support  # noqa: F401

module = importlib.import_module("src.common.secrets")


class SecretsTests(unittest.TestCase):
    def setUp(self):
        module._secrets_client.reset_mock()
        module._ssm_client.reset_mock()

    def tearDown(self):
        module._secret_cache.clear()

    def test_configured_secret_prefers_ssm_parameter(self):
        module._ssm_client.get_parameter.return_value = {
            "Parameter": {"Value": "from-parameter"},
        }

        result = module.get_configured_secret_string(
            parameter_name="/mixroom/test/token",
            secret_arn="arn:aws:secretsmanager:region:123:secret:fallback",
        )

        self.assertEqual(result, "from-parameter")
        module._ssm_client.get_parameter.assert_called_with(
            Name="/mixroom/test/token",
            WithDecryption=True,
        )
        module._secrets_client.get_secret_value.assert_not_called()

    def test_put_secure_parameter_string_writes_securestring(self):
        result = module.put_secure_parameter_string("/mixroom/test/toss/customer", "secret-value")

        self.assertEqual(result, "/mixroom/test/toss/customer")
        module._ssm_client.put_parameter.assert_called_with(
            Name="/mixroom/test/toss/customer",
            Value="secret-value",
            Type="SecureString",
            Overwrite=True,
        )

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
