"""Manual CI signing; no upload or store submission. Run only on macOS."""
import base64
import os
import plistlib
import secrets
import shlex
import subprocess
import tempfile
from pathlib import Path


def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        raise SystemExit(f'{args[0]} failed with exit {result.returncode}')
    return result


def main():
    required = ['IOS_P12_BASE64', 'IOS_P12_PASSWORD', 'IOS_PROFILE_BASE64', 'IOS_TEAM_ID', 'IOS_SIGNING_IDENTITY']
    for name in required:
        if not os.environ.get(name):
            raise SystemExit(f'Missing required signing setting: {name}')
    method = os.environ.get('IOS_EXPORT_METHOD', 'debugging')
    if method not in ('debugging', 'release-testing', 'app-store-connect'):
        raise SystemExit('Unsupported export method')
    team = os.environ['IOS_TEAM_ID']
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        cert = root/'certificate.p12'
        cert.write_bytes(base64.b64decode(os.environ['IOS_P12_BASE64'], validate=True))
        profile = root/'profile.mobileprovision'
        profile.write_bytes(base64.b64decode(os.environ['IOS_PROFILE_BASE64'], validate=True))
        decoded = run(['security','cms','-D','-i',str(profile)],capture_output=True).stdout
        metadata = plistlib.loads(decoded)
        if team not in metadata['TeamIdentifier']:
            raise SystemExit('Provisioning profile team does not match IOS_TEAM_ID')
        identifier = metadata['Entitlements']['application-identifier'].split('.',1)[1]
        installed = Path.home()/'Library/MobileDevice/Provisioning Profiles'/f"{metadata['UUID']}.mobileprovision"
        installed.parent.mkdir(parents=True,exist_ok=True)
        installed.write_bytes(profile.read_bytes())
        keychain = root/'build.keychain-db'
        password = secrets.token_urlsafe(32)
        old_keychains = shlex.split(run(['security','list-keychains','-d','user'],capture_output=True,text=True).stdout)
        try:
            run(['security','create-keychain','-p',password,str(keychain)])
            run(['security','set-keychain-settings','-lut','21600',str(keychain)])
            run(['security','unlock-keychain','-p',password,str(keychain)])
            run(['security','list-keychains','-d','user','-s',str(keychain),*old_keychains])
            run(['security','import',str(cert),'-P',os.environ['IOS_P12_PASSWORD'],'-A','-t','cert','-f','pkcs12','-k',str(keychain)])
            run(['security','set-key-partition-list','-S','apple-tool:,apple:','-k',password,str(keychain)])
            archive = Path('build/signed/TycoonHub.xcarchive').resolve()
            archive.parent.mkdir(parents=True,exist_ok=True)
            run(['xcodebuild','-project','build/ios/TycoonHub.xcodeproj','-scheme','TycoonHub','-configuration','Debug','-sdk','iphoneos','-destination','generic/platform=iOS','-archivePath',str(archive),
                 'CODE_SIGN_STYLE=Manual',f'DEVELOPMENT_TEAM={team}',f"PROVISIONING_PROFILE_SPECIFIER={metadata['Name']}",f"CODE_SIGN_IDENTITY={os.environ['IOS_SIGNING_IDENTITY']}",f'OTHER_CODE_SIGN_FLAGS=--keychain {keychain}','archive'])
            options = root/'ExportOptions.plist'
            options.write_bytes(plistlib.dumps({'method':method,'teamID':team,'signingStyle':'manual','signingCertificate':os.environ['IOS_SIGNING_IDENTITY'],'provisioningProfiles':{identifier:metadata['Name']}}))
            run(['xcodebuild','-exportArchive','-archivePath',str(archive),'-exportPath','build/signed/export','-exportOptionsPlist',str(options)])
        finally:
            subprocess.run(['security','list-keychains','-d','user','-s',*old_keychains],capture_output=True)
            subprocess.run(['security','delete-keychain',str(keychain)],capture_output=True)
            installed.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
