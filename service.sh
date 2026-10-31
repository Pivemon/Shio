#!/system/bin/sh

# Đợi hệ thống boot hoàn tất để system_server có thể nhận lệnh tạo Notification
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
done

LAST_STATE=""

while true; do
    # 1. Tìm đường dẫn của USB DAC trong hệ thống ALSA
    USB_CARD_PATH=""
    for id_file in /proc/asound/card*/id; do
        if grep -iq "USB" "$id_file" 2>/dev/null; then
            USB_CARD_PATH=$(dirname "$id_file")
            break
        fi
    done

    # 2. Nếu tìm thấy DAC đang cắm
    if [ -n "$USB_CARD_PATH" ]; then
        HW_PARAMS="$USB_CARD_PATH/pcm0p/sub0/hw_params"
        
        if [ -f "$HW_PARAMS" ]; then
            STATE=$(cat "$HW_PARAMS")
            
            # Khi có nhạc phát, file này sẽ chứa thông số. Khi dừng, file trả về "closed"
            if [ "$STATE" != "closed" ]; then
                # Bóc tách dữ liệu phần cứng từ ALSA
                FORMAT=$(echo "$STATE" | grep -i "^format:" | awk '{print $2}')
                RATE=$(echo "$STATE" | grep -i "^rate:" | awk '{print $2}')
                CHANNELS=$(echo "$STATE" | grep -i "^channels:" | awk '{print $2}')
                
                # Tính toán Bit-depth từ Format (Vd: S16_LE -> 16, S24_3LE -> 24)
                case "$FORMAT" in
                    *16*) BIT=16 ;;
                    *24*) BIT=24 ;;
                    *32*) BIT=32 ;;
                    *8*)  BIT=8 ;;
                    *)    BIT=16 ;; # Fallback
                esac
                
                # Tính toán Bitrate thực tế (kbps) = (Sample Rate * Bit Depth * Channels) / 1000
                BITRATE=$(( RATE * BIT * CHANNELS / 1000 ))
                
                CURRENT_STATE="${FORMAT}_${RATE}_${CHANNELS}"
                
                # 3. Nếu thông số thay đổi (nhảy sang bài hi-res khác), cập nhật thông báo
                if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
                    # Sử dụng lệnh cmd notification nguyên bản của Android
                    cmd notification post -t "🎵 USB DAC Đang Phát" dac_status "Tần số: ${RATE} Hz | Độ sâu: ${BIT}-bit | Bitrate: ${BITRATE} kbps"
                    LAST_STATE="$CURRENT_STATE"
                fi
            else
                # Nếu DAC đã ngừng giải mã tín hiệu
                if [ "$LAST_STATE" != "closed" ] && [ -n "$LAST_STATE" ]; then
                    cmd notification post -t "🔇 USB DAC" dac_status "Tạm dừng phát nhạc"
                    LAST_STATE="closed"
                fi
            fi
        fi
    else
        # 4. Nếu rút DAC khỏi cổng type-C
        if [ "$LAST_STATE" != "disconnected" ] && [ -n "$LAST_STATE" ]; then
            cmd notification post -t "🔌 USB DAC" dac_status "Đã ngắt kết nối"
            LAST_STATE="disconnected"
        fi
    fi
    
    # Chạy vòng lặp kiểm tra mỗi 2 giây
    sleep 2
done