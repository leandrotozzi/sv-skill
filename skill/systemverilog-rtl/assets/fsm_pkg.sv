// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Types shared by the fsm template: the request/grant state encoding.
//   Package names end in _pkg and the file carries the same name.

`default_nettype none

package fsm_pkg;

    // Request/grant handshake states; each is described on its case arm.
    typedef enum logic [1:0] {
        StIdle,
        StWait,
        StGrant
    } state_e;

endpackage

`resetall
