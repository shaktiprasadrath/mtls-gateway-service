package com.shakti.haproxyserver.capital;

public class CapitalResponse {

    private final String country;
    private final String capital;

    public CapitalResponse(String country, String capital) {
        this.country = country;
        this.capital = capital;
    }

    public String getCountry() {
        return country;
    }

    public String getCapital() {
        return capital;
    }
}
