package com.shakti.haproxyserver.security;

import java.io.IOException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class ClientCertificateLoggingFilter extends OncePerRequestFilter {

    private static final Logger logger = LoggerFactory.getLogger(ClientCertificateLoggingFilter.class);

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        String clientVerify = request.getHeader("X-SSL-Client-Verify");
        String clientCommonName = request.getHeader("X-SSL-Client-CN");
        String clientDistinguishedName = request.getHeader("X-SSL-Client-DN");

        if (clientVerify != null || clientCommonName != null || clientDistinguishedName != null) {
            logger.info(
                    "HAProxy client certificate verification status={}, cn={}, dn={}, path={}",
                    clientVerify,
                    clientCommonName,
                    clientDistinguishedName,
                    request.getRequestURI());
        } else {
            logger.info("Request arrived without forwarded client certificate headers. path={}", request.getRequestURI());
        }

        filterChain.doFilter(request, response);
    }
}
