// USB reports cross through a held payload and request/acknowledge toggles.
// The source never changes held data until the destination acknowledges it.
// Two-flop control synchronizers plus a settling edge precede payload capture.
module x32_keyboard_bridge
    (input wire usb_clk, usb_reset,
     input wire [1 : 0] usb_type,
     input wire usb_error, usb_report,
     input wire [63 : 0] usb_data,
     input wire clk, reset,
     output reg keyboard_present, protocol_error,
     output reg report_valid,
     output reg [63 : 0] report_data);
    reg [67 : 0] held;
    reg request, acknowledge;
    (* ASYNC_REG = "TRUE" *) reg ack_meta, ack_sync, req_meta, req_sync;
    reg [1 : 0] previous_type;
    reg previous_error, settle;
    always @(posedge usb_clk or posedge usb_reset)
    begin
        if (usb_reset)
        begin
            held <= 0;
            request <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            previous_type <= 0;
            previous_error <= 0;
        end
        else
        begin
            ack_meta <= acknowledge;
            ack_sync <= ack_meta;
            if (request == ack_sync &&
                (usb_report || usb_type != previous_type || usb_error != previous_error))
            begin
                held <= {usb_type, usb_error, usb_report, usb_data};
                request <= !request;
                previous_type <= usb_type;
                previous_error <= usb_error;
            end
        end
    end
    always @(posedge clk)
    begin
        if (reset)
        begin
            req_meta <= 0;
            req_sync <= 0;
            acknowledge <= 0;
            settle <= 0;
            keyboard_present <= 0;
            protocol_error <= 0;
            report_valid <= 0;
            report_data <= 0;
        end
        else
        begin
            req_meta <= request;
            req_sync <= req_meta;
            report_valid <= 0;
            if (!settle && req_sync != acknowledge)
                settle <= 1;
            else if (settle)
            begin
                keyboard_present <= held[67 : 66] == 1;
                protocol_error <= held[65];
                report_data <= held[63 : 0];
                report_valid <= held[64] && held[67 : 66] == 1;
                acknowledge <= req_sync;
                settle <= 0;
            end
        end
    end
endmodule
