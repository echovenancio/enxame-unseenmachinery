#!/usr/bin/env python3
"""Regression tests for transient connection failures while Nginx starts."""
import http.client
import sys
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

import test_container


class ContainerReadinessTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(sys, 'argv', ['test_container.py']))
        self.sleep = self.enterContext(patch.object(test_container.time, 'sleep'))
        self.verify = self.enterContext(patch.object(test_container, 'verify'))
        self.urlopen = self.enterContext(patch.object(test_container.urllib.request, 'urlopen'))
        self.ready = MagicMock()
        self.ready.__enter__.return_value.status = 200

    def test_startup_network_errors_retry_then_validate(self):
        for error in [ConnectionResetError(104, 'Connection reset by peer'),
                      http.client.RemoteDisconnected('Remote end closed connection'),
                      urllib.error.URLError('Connection refused'), TimeoutError()]:
            with self.subTest(error=type(error).__name__):
                self.urlopen.reset_mock()
                self.sleep.reset_mock()
                self.verify.reset_mock()
                self.urlopen.side_effect = [error, self.ready]
                test_container.main()
                self.assertEqual(self.urlopen.call_count, 2)
                self.sleep.assert_called_once_with(1)
                self.verify.assert_called_once_with('http://127.0.0.1:8080')

    def test_persistent_network_failure_still_fails(self):
        self.urlopen.side_effect = ConnectionResetError(104, 'Connection reset by peer')
        with self.assertRaisesRegex(RuntimeError, 'Container did not become ready'):
            test_container.main()
        self.assertEqual(self.urlopen.call_count, 30)
        self.verify.assert_not_called()

    def test_failure_after_readiness_is_not_retried(self):
        self.urlopen.return_value = self.ready
        self.verify.side_effect = ConnectionResetError(104, 'Connection reset by peer')
        with self.assertRaises(ConnectionResetError):
            test_container.main()
        self.urlopen.assert_called_once()
        self.sleep.assert_not_called()


if __name__ == '__main__':
    unittest.main()
