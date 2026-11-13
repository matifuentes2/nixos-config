#!/usr/bin/env python3
"""Security invariants without starting privileged services."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import hashlib
import io
import json
import time
import unittest
from unittest.mock import patch


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


supervisor_module = module('job-supervisor')
client = module('job-client')


class JobSecurity(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.now = 100
        with patch.object(supervisor_module.pwd, 'getpwnam', return_value=SimpleNamespace(pw_uid=1000)):
            self.supervisor = supervisor_module.Supervisor({'state': self.directory.name}, clock=lambda: self.now)
        self.request = dict(key='grai:job:claim', job='job', attempt=1, deadline=(time.time() + 1800) * 1000)

    def test_renewal_never_extends_absolute_deadline(self):
        self.supervisor.lease(self.request)
        deadline = self.supervisor.active['deadline']
        self.now += 30
        self.request['deadline'] += 9999999
        self.supervisor.lease(self.request)
        self.assertEqual(self.supervisor.active['deadline'], deadline)
        self.assertEqual(self.supervisor.active['until'], self.now + 60)

    def test_expired_execution_cannot_be_rearmed_by_delayed_renewal(self):
        self.supervisor.lease(self.request)
        self.now += 61
        def stopped():
            self.supervisor.retired.add(self.request['key'])
            self.supervisor.active = None
        with patch.object(self.supervisor, 'stop', side_effect=stopped):
            with self.assertRaisesRegex(ValueError, 'revoked'):
                self.supervisor.lease(self.request)
        self.assertIsNone(self.supervisor.active)

    def test_another_claim_cannot_replace_a_live_execution(self):
        self.supervisor.lease(self.request)
        with self.assertRaisesRegex(ValueError, 'Another'):
            self.supervisor.lease({**self.request, 'key':'grai:other:claim'})

    def test_revocation_survives_a_supervisor_restart(self):
        self.supervisor.retire(self.request['key'])
        self.supervisor.retired.clear()
        with self.assertRaisesRegex(ValueError, 'revoked'):
            self.supervisor.lease(self.request)
        self.assertIsNone(self.supervisor.active)

    def test_invalid_deadlines_and_mismatched_jobs_are_rejected(self):
        for deadline in (float('nan'), float('inf'), 'tomorrow'):
            with self.assertRaisesRegex(ValueError, 'deadline'):
                self.supervisor.lease({**self.request, 'deadline':deadline})
        with self.assertRaisesRegex(ValueError, 'match'):
            self.supervisor.lease({**self.request, 'job':'another'})
        self.assertIsNone(self.supervisor.active)

    def test_controller_credentials_never_cross_protocol_boundary(self):
        value = client.clean({'method':'thread/start','params':{'cwd':'/job','config':{'mcp_servers.t3-code':{'http_headers':{'Authorization':'secret'}},'mcp_servers.t3-code-direct':{'token':'secret'},'model_reasoning_effort':'high','model_providers.attacker':{'auth':'secret'}},'input':[{'text':'Preserve authored café'}]}})
        self.assertNotIn('secret', str(value))
        self.assertEqual(value['params']['config'],{'model_reasoning_effort':'high'})
        self.assertEqual(value['params']['input'][0]['text'],'Preserve authored café')

    def test_retention_requires_completed_and_reviewed_ticket(self):
        root = Path(self.directory.name)
        evidence = root / 'evidence'
        evidence.mkdir()
        token = root / 'token'
        token.write_text('test-token')
        self.supervisor.config.update(evidence=str(evidence), supportToken=str(token), supportUrl='https://support.test', worktrees=str(root / 'worktrees'))
        key = hashlib.sha256(self.request['key'].encode()).hexdigest()
        artifact = evidence / key
        artifact.mkdir()
        (artifact / 'retention.json').write_text(json.dumps(dict(ticket='ticket',completed=(time.time()-8*86400)*1000)))
        opener = SimpleNamespace(open=lambda *a, **kw: io.BytesIO(json.dumps(dict(ticket=dict(status='review'))).encode()))
        with patch.object(supervisor_module.urllib.request,'build_opener',return_value=opener):
            self.supervisor.cleanup()
        self.assertTrue(artifact.exists())
        opener.open=lambda *a, **kw: io.BytesIO(json.dumps(dict(ticket=dict(status='closed'))).encode())
        with patch.object(supervisor_module.urllib.request,'build_opener',return_value=opener):
            self.supervisor.cleanup()
        self.assertFalse(artifact.exists())

    def test_sparse_files_cannot_amplify_export_beyond_job_disk_budget(self):
        archive = Path(self.directory.name) / 'archive'
        repo = archive / 'data' / 'repo'
        repo.mkdir(parents=True)
        with (repo / 'sparse').open('wb') as file:
            file.truncate(3 * 1024**3)
        with self.assertRaisesRegex(RuntimeError, 'Export budget'):
            self.supervisor.export(archive, Path(self.directory.name))


if __name__ == '__main__':
    unittest.main()
