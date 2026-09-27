import ballerina/crypto;
import ballerina/http;
import ballerina/time;
import ballerina/test;


// The gateway-assertion contract: a valid assertion is accepted, a different
// key's signature is a 401, a tampered payload is a 401, and a security: []
// resource answers 200 with no assertion at all.

final http:Client apiClient = checkpanic new ("http://localhost:9090");

@test:Config {}
function testValidAssertionAccepted() {
    AssertionKey key = assertionKey();
    string assertion = mintAssertion(key, "uuid-1234", "test-employee",
        "openid profile email group ou claims:read claims:write claims:submit");
    map<string|string[]> assertionHeader = {};
    assertionHeader[key.header] = assertion;
    json payload = {title: "Valid assertion claim"};
    json|http:ClientError response = apiClient->post("/me/claims", payload,
        headers = assertionHeader);
    test:assertTrue(response is json, msg = "a valid assertion must reach the endpoint");
}

@test:Config {}
function testDifferentKeySignatureRejected() {
    AssertionKey key = assertionKey();
    crypto:PrivateKey otherKey = differentKey();
    // sign with the OTHER key, present under the trusted header
    time:Utc now = time:utcNow();
    json header = {alg: "RS256", typ: "JWT"};
    json payload = {sub: "uuid-1234", username: "test-employee",
        scope: "openid claims:read", iss: key.issuer, exp: now[0] + 900, iat: now[0]};
    string signingInput = base64UrlOf(header.toJsonString()) + "."
        + base64UrlOf(payload.toJsonString());
    byte[] signature = checkpanic crypto:signRsaSha256(signingInput.toBytes(), otherKey);
    string forged = signingInput + "." + base64UrlOfBytes(signature);
    http:Request request = new;
    request.setHeader(key.header, forged);
    int|http:ClientError status = apiClient->post("/me/claims", request,
        mediaType = "application/json", targetType = int);
    test:assertTrue(status is http:ClientError,
        msg = "a different-key signature must not be served");
    if status is http:ClientRequestError {
        int code = status.detail().statusCode;
        test:assertEquals(code, 401, msg = "a forged assertion must 401");
    }
}

@test:Config {}
function testTamperedPayloadRejected() {
    AssertionKey key = assertionKey();
    string tampered = mintTamperedAssertion(key, "uuid-1234", "test-employee",
        "openid claims:read");
    string assertionName = key.header;
    map<string|string[]> assertionHeader = {assertionName: tampered};
    json|http:ClientError response = apiClient->get("/people", headers = assertionHeader);
    test:assertTrue(response is http:ClientError,
        msg = "an edited payload must not be served");
    if response is http:ClientRequestError {
        int code = response.detail().statusCode;
        test:assertEquals(code, 401, msg = "a tampered assertion must 401");
    }
}

@test:Config {}
function testNoAssertionOnProtectedResourceIs401() {
    AssertionKey key = assertionKey();
    _ = key;
    json|http:ClientError response = apiClient->get("/me/claims");
    test:assertTrue(response is http:ClientError, msg = "expected a 401, got a success");
    if response is http:ClientRequestError {
        int code = response.detail().statusCode;
        test:assertEquals(code, 401, msg = "no assertion on a protected resource must 401");
    }
}

@test:Config {}
function testPublicResourcesAnswerWithoutAssertion() {
    AssertionKey key = assertionKey();
    _ = key;
    string health = checkpanic apiClient->get("/health");
    test:assertEquals(health, "ok");
    string[] categories = checkpanic apiClient->get("/categories");
    test:assertEquals(categories.length(), 5, msg = "the category list must be public");
}