package com.shakti.haproxyserver.capital;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class CapitalControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void returnsCapitalForCountryQueryParam() throws Exception {
        mockMvc.perform(get("/capital").param("country", "India"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.country").value("India"))
                .andExpect(jsonPath("$.capital").value("New Delhi"));
    }

    @Test
    void returnsCapitalForCountryPath() throws Exception {
        mockMvc.perform(get("/capital/france"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.country").value("France"))
                .andExpect(jsonPath("$.capital").value("Paris"));
    }

    @Test
    void returnsNotFoundForUnknownCountry() throws Exception {
        mockMvc.perform(get("/capital").param("country", "Atlantis"))
                .andExpect(status().isNotFound());
    }
}
