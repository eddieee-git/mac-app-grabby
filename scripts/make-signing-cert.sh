#!/bin/zsh
# 이 Mac에서만 쓰는 코드 서명 인증서("Grabby Local Signing")를 만들어 로그인 키체인에 넣는다.
# Apple 계정은 필요 없다. 이 인증서로 서명하면 다시 빌드해도 화면 기록 권한이 풀리지 않는다.
# 한 번만 실행하면 된다. 키체인 암호를 물어볼 수 있다.
set -e
name="Grabby Local Signing"
if security find-certificate -c "$name" >/dev/null 2>&1; then
    echo "이미 있어요: $name"
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/cert.conf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.conf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
    -out "$dir/cert.p12" -passout pass:grabby -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" -out "$dir/cert.p12" -passout pass:grabby
security import "$dir/cert.p12" -k ~/Library/Keychains/login.keychain-db -P grabby -T /usr/bin/codesign

echo "만들었어요: $name"
echo "이제 ./scripts/build-app.sh로 다시 빌드하고 설치한 뒤, 화면 기록 권한을 한 번만 다시 켜 주세요."
