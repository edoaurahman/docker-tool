#!/bin/bash

# Fungsi untuk menampilkan header
header() {
    clear
    echo "======================================"
    echo "  Docker Container CPU Limiter Tool   "
    echo "======================================"
    echo
}

# Fungsi untuk mendapatkan jumlah CPU core yang tersedia
get_cpu_count() {
    docker info --format '{{.NCPU}}' 2>/dev/null || grep -c ^processor /proc/cpuinfo
}

# Fungsi untuk memeriksa apakah container sudah di-limit
check_limit() {
    local container_id=$1
    docker inspect --format '{{.HostConfig.NanoCpus}}' "$container_id" | grep -v '^0$' > /dev/null
    if [ $? -eq 0 ]; then
        echo "[LIMITED]"
    else
        echo "[UNLIMITED]"
    fi
}

# Main program
cpu_count=$(get_cpu_count)
max_cpu_percent=$((cpu_count * 100))

while true; do
    header
    echo "Sistem memiliki $cpu_count CPU core (maksimal $max_cpu_percent% total)"
    echo "Daftar Container yang Berjalan:"
    echo "--------------------------------------"
    
    # Mendapatkan list container yang berjalan
    containers=()
    while IFS= read -r line; do
        containers+=("$line")
    done < <(docker ps --format "{{.ID}}|{{.Names}}|{{.Image}}")
    
    # Menampilkan container dengan nomor urut
    for i in "${!containers[@]}"; do
        IFS='|' read -r id name image <<< "${containers[$i]}"
        status=$(check_limit "$id")
        printf "%2d) %-20s %-30s %s\n" "$((i+1))" "$name" "$image" "$status"
    done
    
    echo "--------------------------------------"
    echo "0) Keluar"
    echo
    read -p "Pilih container (1-${#containers[@]}) atau 0 untuk keluar: " choice
    
    # Keluar jika memilih 0
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        echo "Keluar..."
        exit 0
    fi
    
    # Validasi pilihan
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#containers[@]}" ]; then
        echo "Pilihan tidak valid!"
        sleep 2
        continue
    fi
    
    # Mendapatkan ID container yang dipilih
    index=$((choice-1))
    IFS='|' read -r container_id container_name container_image <<< "${containers[$index]}"
    
    header
    echo "Container yang dipilih:"
    echo "  Nama  : $container_name"
    echo "  ID    : $container_id"
    echo "  Image : $container_image"
    echo "  Status: $(check_limit "$container_id")"
    echo
    
    # Meminta input persentase CPU
    while true; do
        read -p "Masukkan persentase CPU (1-$max_cpu_percent, 0 untuk menghapus limit): " cpu_percent
        if [[ "$cpu_percent" =~ ^[0-9]+$ ]] && [ "$cpu_percent" -ge 0 ] && [ "$cpu_percent" -le "$max_cpu_percent" ]; then
            break
        else
            echo "Persentase harus antara 0-$max_cpu_percent!"
        fi
    done
    
    # Mengupdate limit CPU
    if [ "$cpu_percent" -eq 0 ]; then
        echo "Menghapus limit CPU untuk container $container_name..."
        docker update --cpus 0 "$container_id" > /dev/null
    else
        # Konversi persentase ke fractional CPU cores (misal 50% = 0.5 core)
        cpu_cores=$(awk "BEGIN {printf \"%.2f\", $cpu_percent/100}")
        echo "Mengatur limit CPU $cpu_percent% ($cpu_cores core) untuk container $container_name..."
        docker update --cpus "$cpu_cores" "$container_id" > /dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo "Berhasil diupdate!"
    else
        echo "Gagal mengupdate container!"
    fi
    
    read -p "Tekan Enter untuk melanjutkan..."
done
