idf_component_register(
    SRCS
        "main.c"
        "ct_lcd.c"
        "ct_rects.c"
        "ct_props.c"
        "ct_mascot.c"
        "ct_model.c"
        "ct_ui.c"
        "ct_ble.c"
        "ct_led.c"
    INCLUDE_DIRS "."
    REQUIRES driver esp_timer nvs_flash bt json
)
