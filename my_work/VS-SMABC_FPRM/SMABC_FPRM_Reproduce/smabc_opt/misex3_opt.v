// SMABC Optimized Netlist (ABC-friendly)
module misex3_opt(i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13, f);
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
input i12;
input i13;
output f;
assign f = ~i0 & ~i1 & ~i2 & ~i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8 & ~i9 & ~i10 & ~i11 & ~i12 & ~i13;
endmodule
