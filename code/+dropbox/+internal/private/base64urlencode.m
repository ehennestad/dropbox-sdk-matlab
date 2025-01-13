function encoded = base64urlencode(input)
    % Convert base64 to base64 URL-safe encoding
    encoded = regexprep(input, '\+', '-');
    encoded = regexprep(encoded, '/', '_');
end
