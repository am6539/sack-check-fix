# sack-check-fix
Check vul &amp; fix SACK Panic

## Cách dùng
Để kiểm tra xem Linux kernel có dính lỗi hay không thì chạy:

 `$ sudo ./sack_check_fix.sh check`

- Nếu lỗi: Vulnerable
- Không lỗi: Not vulnerable

## Khi kiểm tra xong mà báo lỗi, cách fix

 `$ sudo ./sack_check_fix.sh install`

Chạy xong check lại xem còn lỗi hay không!

## Restore
Nếu muốn restore lại setting chạy script ./restore.sh
