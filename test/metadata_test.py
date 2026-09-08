"""Run pinned scripts, with explicit network fixtures and project-local temp shims."""
import json, os, pathlib, pty, select, subprocess, tempfile, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
(ROOT/'.test-artifacts').mkdir(exist_ok=True)
WORK=ROOT.parent
TX='11'*32
ADDR='stake_test1'+'q'*53

class MetadataAuthoring(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=ROOT/'.test-artifacts'); self.addCleanup(self.tmp.cleanup)
        self.dir=pathlib.Path(self.tmp.name); shims=self.dir/'bin';shims.mkdir()
        # pandoc is checked but NEVER invoked in this version; fail if that changes.
        scripts={'pandoc':'#!/bin/bash\nexit 99\n',
          'mktemp':'#!/bin/bash\nexec /usr/bin/mktemp "'+str(self.dir)+'/metadata.XXXXXXXX"\n',
          'curl':'''#!/usr/bin/env python3
import os,json,sys,pathlib
u=sys.argv[-1];mode=os.environ.get('AUDIT_REMOTE_MODE','ok')
if mode=='offline': sys.exit(22)
if 'common.jsonld' in u: print(pathlib.Path(os.environ['AUDIT_CONTEXT']).read_text())
elif '/epoch_params?' in u: print(json.dumps([{'epoch_no':500,'gov_action_deposit':'1000000000'}]))
elif '/tip?' in u: print(json.dumps([{'epoch_no':501 if mode=='stale' else 500}]))
elif 'parameters.json' in u: print(json.dumps({'govActionDeposit':2000000000 if mode=='disagree' else 1000000000}))
else: sys.exit(99)
'''}
        for n,s in scripts.items(): p=shims/n;p.write_text(s);p.chmod(0o755)
        self.env={**os.environ,'PATH':str(shims)+':'+os.environ['PATH'],'AUDIT_CONTEXT':str(ROOT/'test/fixtures/info-context.jsonld')}
        self.md=self.dir/'action.md';self.md.write_text('## Title\nAudit action\n## Abstract\nAbstract\n## Motivation\nMotivation\n## Rationale\nRationale\n## References\n\n## Authors\n')
    def run_script(self,ref=None,mode='ok',network='preview'):
        args=['bash',str(ROOT/'scripts/metadata-create.sh'),str(self.md),'--governance-action-type','info','--deposit-return-addr',ADDR,'--network',network,'--no-cip179-survey']
        if ref is not None: args+=['--cip179-survey-ref',ref]
        self.env['AUDIT_REMOTE_MODE']=mode
        r=subprocess.run(args,env=self.env,capture_output=True,text=True,timeout=20)
        (ROOT/'.test-artifacts/script-cases').mkdir(exist_ok=True)
        (ROOT/'.test-artifacts/script-cases'/self.id().split('.')[-1]).write_text(r.stdout+r.stderr)
        return r
    def doc(self): return json.loads(self.md.with_suffix('.jsonld').read_text())
    def test_link_default_index(self):
        r=self.run_script('AB'*32);self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.doc()['body']['cip179'],dict(specVersion=5,kind='survey-link',surveyTxId='ab'*32,surveyIndex=0))
        self.assertIn('cip179',self.doc()['@context']['body']['@context'])
        (ROOT/'.test-artifacts/authored-info.jsonld').write_text(json.dumps(self.doc(),indent=2)+'\n')
    def test_nonzero_index(self):
        r=self.run_script(TX+'#65535');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.doc()['body']['cip179']['surveyIndex'],65535)
    def test_no_link_regression(self):
        r=self.run_script();self.assertEqual(r.returncode,0,r.stderr);self.assertNotIn('cip179',self.doc()['body']);self.assertIsInstance(self.doc()['@context'],str)
    def test_bad_reference(self): self.assertNotEqual(self.run_script('bad').returncode,0)
    def test_negative_index(self): self.assertNotEqual(self.run_script(TX+'#-1').returncode,0)
    def test_index_above_uint16(self): self.assertNotEqual(self.run_script(TX+'#65536').returncode,0)
    def test_AUD_S01_index_above_shell_integer(self): self.assertNotEqual(self.run_script(TX+'#99999999999999999999999999999').returncode,0)
    def test_stale_epoch_fails_closed(self): self.assertNotEqual(self.run_script(TX,mode='stale').returncode,0)
    def test_deposit_disagreement_fails_closed(self): self.assertNotEqual(self.run_script(TX,mode='disagree').returncode,0)
    def test_remote_error_fails_closed(self): self.assertNotEqual(self.run_script(TX,mode='offline').returncode,0)
    def test_wrong_network_fails_closed(self): self.assertNotEqual(self.run_script(TX,network='mainnet').returncode,0)


    def test_leading_zeros_are_decimal(self):
        r=self.run_script(TX+'#000000000000008');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.doc()['body']['cip179']['surveyIndex'],8)
    def test_same_deposit_wrong_node_is_rejected(self):
        cli=self.dir/'bin/cardano-cli'
        cli.write_text('''#!/bin/bash\n[[ "$*" == *"--testnet-magic 2"* ]] && exit 1\necho '{"currentPParams":{"govActionDeposit":1000000000}}'\n''');cli.chmod(0o755)
        self.env['CARDANO_NODE_SOCKET_PATH']=str(self.dir/'preprod.socket')
        self.assertNotEqual(self.run_script(TX).returncode,0)
    def test_matching_node_uses_explicit_magic(self):
        cli=self.dir/'bin/cardano-cli'
        cli.write_text('''#!/bin/bash\n[[ "$*" == *"--testnet-magic 2"* ]] || exit 1\necho '{"currentPParams":{"govActionDeposit":1000000000}}'\n''');cli.chmod(0o755)
        self.env['CARDANO_NODE_SOCKET_PATH']=str(self.dir/'preview.socket')
        self.env['CARDANO_NODE_NETWORK_ID']='1'
        self.assertEqual(self.run_script(TX).returncode,0)

if __name__=='__main__': unittest.main(verbosity=2)
