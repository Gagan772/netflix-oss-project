package com.netflix.oss.userbff.config;

import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.io.HttpClientConnectionManager;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactory;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactoryBuilder;
import org.apache.hc.client5.http.ssl.NoopHostnameVerifier;
import org.apache.hc.core5.ssl.SSLContextBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import java.io.File;

@Configuration
public class MtlsConfig {

    @Value("${middleware.ssl.trust-store}")
    private String trustStorePath;

    @Value("${middleware.ssl.trust-store-password}")
    private String trustStorePassword;

    @Value("${middleware.ssl.key-store}")
    private String keyStorePath;

    @Value("${middleware.ssl.key-store-password}")
    private String keyStorePassword;

    @Value("${middleware.ssl.key-password}")
    private String keyPassword;

    @Bean
    public RestTemplate mtlsRestTemplate() throws Exception {
        File trustStoreFile = new File(trustStorePath);
        File keyStoreFile = new File(keyStorePath);

        SSLContext sslContext = SSLContextBuilder.create()
                .loadTrustMaterial(trustStoreFile, trustStorePassword.toCharArray())
                .loadKeyMaterial(keyStoreFile, keyStorePassword.toCharArray(), keyPassword.toCharArray())
                .build();

        // Use NoopHostnameVerifier because middleware IP is dynamic in cloud environment
        // mTLS still validates the certificate chain through the CA
        SSLConnectionSocketFactory sslSocketFactory = SSLConnectionSocketFactoryBuilder.create()
                .setSslContext(sslContext)
                .setHostnameVerifier(NoopHostnameVerifier.INSTANCE)
                .build();

        HttpClientConnectionManager connectionManager = PoolingHttpClientConnectionManagerBuilder.create()
                .setSSLSocketFactory(sslSocketFactory)
                .build();

        CloseableHttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .build();

        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout(10000);

        return new RestTemplate(factory);
    }
}
