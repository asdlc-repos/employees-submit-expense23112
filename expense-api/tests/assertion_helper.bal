import ballerina/crypto;
import ballerina/lang.array as la;
import ballerina/time;

// The gateway-assertion trio is minted and exported by run_tests.sh BEFORE
// bal test starts the listener; this module reuses those same key files.

public type AssertionKey record {|
    crypto:PrivateKey privateKey;
    string issuer;
    string header;
|};

string keyDir = "/tmp/expense-api-test-keys";

public function assertionKey() returns AssertionKey {
    crypto:PrivateKey|crypto:Error key = crypto:decodeRsaPrivateKeyFromKeyFile(keyDir + "/gateway.key");
    if key is crypto:Error {
        panic key;
    }
    return {privateKey: key, issuer: "aep-gateway-test", header: "x-jwt-assertion"};
}

// A second, different keypair whose signatures must be rejected.
public function differentKey() returns crypto:PrivateKey {
    crypto:PrivateKey|crypto:Error key = crypto:decodeRsaPrivateKeyFromKeyFile(keyDir + "/other.key");
    if key is crypto:Error {
        panic key;
    }
    return key;
}

// Signs a JWT-shaped assertion the interceptor verifies with jwt:validate.
public function mintAssertion(AssertionKey key, string subject, string username, string scopes)
        returns string {
    json header = {alg: "RS256", typ: "JWT"};
    time:Utc now = time:utcNow();
    json payload = {sub: subject, username: username, scope: scopes, iss: key.issuer,
        exp: now[0] + 900, iat: now[0]};
    string signingInput = base64UrlOf(header.toJsonString()) + "." + base64UrlOf(payload.toJsonString());
    byte[] signature = checkpanic crypto:signRsaSha256(signingInput.toBytes(), key.privateKey);
    return signingInput + "." + base64UrlOfBytes(signature);
}

// Signs a payload that was edited after signing: the signature covers other
// bytes, so validation must fail.
public function mintTamperedAssertion(AssertionKey key, string subject, string username, string scopes)
        returns string {
    string valid = mintAssertion(key, subject, username, scopes);
    string[] parts = re `\.`.split(valid);
    string decoded = base64UrlDecode(parts[1]);
    json payload = checkpanic decoded.fromJsonString();
    string edited = checkpanic payload.toJsonString();
    edited = re `"sub":"[^"]+"`.replaceAll(edited, "\"sub\":\"attacker\"");
    return parts[0] + "." + base64UrlOf(edited) + "." + parts[2];
}

public function base64UrlOf(string content) returns string {
    return base64UrlOfBytes(content.toBytes());
}

public function base64UrlOfBytes(byte[] content) returns string {
    string standard = la:toBase64(content);
    standard = re `\+`.replaceAll(standard, "-");
    standard = re `/`.replaceAll(standard, "_");
    int? padIndex = standard.indexOf("=");
    if padIndex is int {
        standard = standard.substring(0, padIndex);
    }
    return standard;
}
function base64UrlDecode(string encoded) returns string {
    string standard = re `-`.replaceAll(encoded, "+");
    standard = re `_`.replaceAll(standard, "/");
    string padded = standard;
    int remainder = standard.length() % 4;
    if remainder == 2 {
        padded = standard + "==";
    } else if remainder == 3 {
        padded = standard + "=";
    }
    byte[]|error decodedBytes = la:fromBase64(padded);
    if decodedBytes is byte[] {
        return checkpanic string:fromBytes(decodedBytes);
    }
    return encoded;
}
