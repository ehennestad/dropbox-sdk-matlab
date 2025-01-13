function hash = sha256(data)
    % Helper function to compute the SHA256 hash
    persistent hasher;
    if isempty(hasher)
        hasher = java.security.MessageDigest.getInstance('SHA-256');
    end
    
    hasher.update(uint8(char(data)));
    hash = typecast(hasher.digest, 'uint8');
    hash = char(org.apache.commons.codec.binary.Base64.encodeBase64(hash));
    
    if iscolumn(hash)
        hash = hash';
    end
    hash = regexprep(hash, '=', ''); % Remove padding
end
