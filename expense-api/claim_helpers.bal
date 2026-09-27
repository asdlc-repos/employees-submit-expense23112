import expense_api.types as ty;
function claimOfLine(string lineId) returns ty:ClaimRow|StoreError {
    ty:LineRow|StoreError line = appStore.getLineById(lineId);
    if line is StoreError {
        return line;
    }
    return appStore.getClaim(line.claimId);
}