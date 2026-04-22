// SMABC Optimized Netlist (ABC-friendly)
module br2_opt(i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, f);
input i0;
input i1;
input i2;
input i3;
input i4;
input i5;
input i6;
input i7;
input i8;
input i9;
input i10;
input i11;
output f;
wire t0;
wire t1;
wire s0;
assign t0 = ~i0 & ~i1 & ~i2 & ~i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8 & ~i9 & ~i10 & ~i11;
assign t1 = ~i0 & ~i1 & ~i2 & ~i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8 & ~i9 & ~i10 & i11;
assign s0 = t0 | t1;
assign f = s0;
endmodule
