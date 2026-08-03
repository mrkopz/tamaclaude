idf_component_register(
    SRCS
        "main.c"
        "ct_lcd.c"
        "ct_rects.c"
        "ct_props.c"
        "ct_mascot.c"
        "ct_model.c"
        "ct_pages.c"
        "ct_paint.c"
        "ct_fonts.c"
        "ct_ui.c"
        "ct_age.c"
        "ct_weather.c"
        "ct_weather_ui.c"
        "ct_crypto.c"
        "ct_crypto_ui.c"
        "ct_ble.c"
        "ct_wifi.c"
        "ct_lan.c"
        "ct_led.c"
        "ct_font_thai_12.c"
        "ct_font_thai_14.c"
    INCLUDE_DIRS "."
    REQUIRES driver esp_timer nvs_flash bt json esp_wifi esp_netif esp_event
             lwip mbedtls espressif__mdns
)
