package com.shakti.haproxyserver.capital;

import java.util.Optional;

import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class CapitalService {

    private final JdbcTemplate jdbcTemplate;

    public CapitalService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public Optional<CapitalResponse> findByCountry(String country) {
        String normalizedCountry = country == null ? "" : country.trim();

        if (normalizedCountry.isBlank()) {
            return Optional.empty();
        }

        try {
            return Optional.ofNullable(jdbcTemplate.queryForObject(
                    "SELECT country, capital FROM country_capitals WHERE LOWER(country) = LOWER(?)",
                    (rs, rowNum) -> new CapitalResponse(
                            rs.getString("country"),
                            rs.getString("capital")),
                    normalizedCountry));
        } catch (EmptyResultDataAccessException ex) {
            return Optional.empty();
        }
    }
}
