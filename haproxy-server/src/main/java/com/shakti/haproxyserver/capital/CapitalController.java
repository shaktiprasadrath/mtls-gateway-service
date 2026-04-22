package com.shakti.haproxyserver.capital;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CapitalController {

    private final CapitalService capitalService;

    public CapitalController(CapitalService capitalService) {
        this.capitalService = capitalService;
    }

    @GetMapping("/capital")
    public ResponseEntity<CapitalResponse> getCapital(@RequestParam String country) {
        return capitalService.findByCountry(country)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping("/capital/{country}")
    public ResponseEntity<CapitalResponse> getCapitalByPath(@PathVariable String country) {
        return getCapital(country);
    }
}
