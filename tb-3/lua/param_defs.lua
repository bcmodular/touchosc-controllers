-- param_defs.lua — Task 2.2a canonical synthesis-parameter table.
-- Included as the LAST entry in toscbuild.json root include list (so it is
-- prepended first and therefore executes first in the concatenated chunk).
-- bcr_map.lua / enc_map.lua / patch_manager.lua all derive their primary tables
-- from Params.LIST; nothing reads Params at runtime after that.
--
-- Row schema (all fields optional except as noted):
--   path          "section,enc" UI key → ENC_SEND_MAP, SW_SEND_MAP, PARAM_ID_MAP
--   addr          {a1,a2,a3,a4} SysEx address
--   bits          7 or 16
--   signed        s7 offset-encoded (raw 64 = 0)
--   bipolar       display ±value around centre
--   center        explicit centre raw value (default floor(max/2))
--   semitoneRange display ±N semitones (raw N → ±(N+1) st)
--   max           full-scale (omit to use default: bits=7 → 127, bits=16 → 255)
--   id            param-assign ID → PARAM_ID_MAP or SW_PARAM_ID_MAP
--   name          display name for assign labels
--   bcr           BCR1 CC number → BCR.MAP
--   nrpn          NRPN number → BCR.NRPN_MAP (no BCR encoder for nrpn=5,6,7)
--   sw            true → SW_SEND_MAP entry; REGISTRY kind="sw",sw=true
--   btn           true → standalone button; SW_SEND_MAP btn=true; REGISTRY btn=true
--   par           REGISTRY parent group (only ring_mod_group; name collision guard)
--   regSp         REGISTRY kind="sp",sp=regSp entry (no enc in REGISTRY)
--   regU16        with regSp: REGISTRY u16=true (assign param ID slots)
--   encSp         ENC_SEND_MAP sp=encSp entry, no addr (global_tuning only)

local Params = {}

-- Rows are ordered within each SysEx block to match HEAD REGISTRY entry order,
-- so the derived REGISTRY arrays are identically ordered for the harness.

Params.LIST = {

  -- ========== LFO  10 00 00 00 ==========
  { path="lfo_group,lfo_rate_enc",      addr={0x10,0x00,0x00,0x00}, bits=7,  bcr=9,  id= 0, name="LFO RATE"     },
  { path="lfo_group,lfo_delay_enc",     addr={0x10,0x00,0x00,0x01}, bits=7,  bcr=11, id= 1, name="LFO DELAY"    },
  { path="lfo_group,lfo_wave_saw_enc",  addr={0x10,0x00,0x00,0x02}, bits=7,  bcr=13, id= 2, name="LFO SAW"      },
  { path="lfo_group,lfo_wave_sqr_enc",  addr={0x10,0x00,0x00,0x03}, bits=7,  bcr=14, id= 3, name="LFO SQR"      },
  { path="lfo_group,lfo_wave_tri_enc",  addr={0x10,0x00,0x00,0x04}, bits=7,  bcr=12, id= 4, name="LFO TRI"      },
  { path="lfo_group,lfo_wave_sin_enc",  addr={0x10,0x00,0x00,0x05}, bits=7,  bcr=15, id= 5, name="LFO SIN"      },
  { path="lfo_group,lfo_cv_offset_enc", addr={0x10,0x00,0x00,0x06}, bits=7,  bcr=10, id= 6, name="LFO CV OFFSET"},
  { path="lfo_group,lfo_wave_sh_enc",   addr={0x10,0x00,0x00,0x07}, bits=7,  bcr=16, id= 7, name="LFO S&H"      },
  { path="vco_group,vco_lfo_depth_enc", addr={0x10,0x00,0x00,0x08}, bits=7,  signed=true, bcr=7,  id= 8, name="VCO LFO DEPTH" },
  { path="vcf_group,vcf_lfo_depth_enc", addr={0x10,0x00,0x00,0x09}, bits=7,  signed=true, bcr=94, id= 9, name="VCF LFO DEPTH" },
  { path="vca_group,vca_lfo_depth_enc", addr={0x10,0x00,0x00,0x0A}, bits=7,  signed=true, bcr=85, id=10, name="VCA LFO DEPTH" },
  -- LFO sw_button children (same paths, different addr)
  { path="lfo_group,lfo_rate_enc",      addr={0x10,0x00,0x00,0x0B}, bits=7,  sw=true, bcr=41, id=11, name="LFO BPM SYNC"  },
  { path="lfo_group,lfo_cv_offset_enc", addr={0x10,0x00,0x00,0x0C}, bits=7,  sw=true, bcr=42, id=12, name="LFO RETRIGGER" },

  -- ========== TUNING (CV OFFSET)  10 00 02 00 ==========
  -- NOTE: spec labels off=0 as SQR, off=2 as SAW, but hardware is reversed.
  -- id 14 = SAW TUNING @ addr off=0x00 (NRPN 1)
  -- id 13 = SQR TUNING @ addr off=0x02 (NRPN 2)  — intentional ID↔addr swap
  { path="tuning_group,saw_tuning_enc",      addr={0x10,0x00,0x02,0x00}, bits=16, bipolar=true, max=151, center=127, nrpn=1, id=14, name="SAW TUNING"      },
  { path="tuning_group,sqr_tuning_enc",      addr={0x10,0x00,0x02,0x02}, bits=16, bipolar=true, max=151, center=127, nrpn=2, id=13, name="SQR TUNING"      },
  { path="tuning_group,ring_sin_tuning_enc", addr={0x10,0x00,0x02,0x04}, bits=16, bipolar=true, max=151, center=127, nrpn=3, id=15, name="RING+SIN TUNING" },
  -- ENC-only special (plain MIDI CC 104, no SysEx addr)
  { path="tuning_group,tuning_enc", encSp="global_tuning" },

  -- ========== CROSS MODULATION  10 00 04 00 ==========
  { path="cross_mod_group,sqr_saw_enc",   addr={0x10,0x00,0x04,0x00}, bits=7, signed=true, id=16, name="CM SQR>SAW"   },
  { path="cross_mod_group,saw_saw_enc",   addr={0x10,0x00,0x04,0x02}, bits=7, signed=true, id=18, name="CM SAW>SAW"   },
  { path="cross_mod_group,white_saw_enc", addr={0x10,0x00,0x04,0x03}, bits=7, signed=true, id=19, name="CM WHITE>SAW" },
  { path="cross_mod_group,pink_saw_enc",  addr={0x10,0x00,0x04,0x04}, bits=7, signed=true, id=20, name="CM PINK>SAW"  },
  { path="cross_mod_group,sqr_sqr_enc",   addr={0x10,0x00,0x04,0x05}, bits=7, signed=true, id=21, name="CM SQR>SQR"   },
  { path="cross_mod_group,saw_sqr_enc",   addr={0x10,0x00,0x04,0x07}, bits=7, signed=true, id=23, name="CM SAW>SQR"   },
  { path="cross_mod_group,white_sqr_enc", addr={0x10,0x00,0x04,0x08}, bits=7, signed=true, id=24, name="CM WHITE>SQR" },
  { path="cross_mod_group,pink_sqr_enc",  addr={0x10,0x00,0x04,0x09}, bits=7, signed=true, id=25, name="CM PINK>SQR"  },

  -- ========== RING MODULATION  10 00 06 00 ==========
  -- par="ring_mod_group": enc names collide with vco_group; REGISTRY uses parent
  { path="ring_mod_group,saw_enc",   addr={0x10,0x00,0x06,0x00}, bits=7, par="ring_mod_group", id=26, name="RM SAW DEPTH"   },
  { path="ring_mod_group,sqr_enc",   addr={0x10,0x00,0x06,0x01}, bits=7, par="ring_mod_group", id=27, name="RM SQR DEPTH"   },
  { path="ring_mod_group,ring_enc",  addr={0x10,0x00,0x06,0x04}, bits=7, par="ring_mod_group", id=30, name="RM RING DEPTH"  },
  { path="ring_mod_group,white_enc", addr={0x10,0x00,0x06,0x05}, bits=7, par="ring_mod_group", id=31, name="RM WHITE DEPTH" },
  { path="ring_mod_group,pink_enc",  addr={0x10,0x00,0x06,0x06}, bits=7, par="ring_mod_group", id=32, name="RM PINK DEPTH"  },
  { path="ring_mod_group,depth_enc", addr={0x10,0x00,0x06,0x0B}, bits=7, par="ring_mod_group", id=37, name="RM DEPTH"       },

  -- ========== VCO levels  10 00 08 00 ==========
  { path="vco_group,saw_enc",   addr={0x10,0x00,0x08,0x00}, bits=7, bcr= 1, id=40, name="VCO SAW LEVEL"   },
  { path="vco_group,sqr_enc",   addr={0x10,0x00,0x08,0x01}, bits=7, bcr= 2, id=41, name="VCO SQR LEVEL"   },
  { path="vco_group,sin_enc",   addr={0x10,0x00,0x08,0x04}, bits=7, bcr= 3, id=44, name="VCO SIN LEVEL"   },
  { path="vco_group,white_enc", addr={0x10,0x00,0x08,0x05}, bits=7, bcr= 4, id=45, name="VCO WHITE LEVEL" },
  { path="vco_group,pink_enc",  addr={0x10,0x00,0x08,0x06}, bits=7, bcr= 5, id=46, name="VCO PINK LEVEL"  },
  { path="vco_group,ring_enc",  addr={0x10,0x00,0x08,0x07}, bits=7, bcr=17, id=47, name="VCO RING LEVEL"  },
  -- VCO source switches (sw_button children, same paths, different addr)
  { path="vco_group,saw_enc",   addr={0x10,0x00,0x08,0x08}, bits=7, sw=true, bcr=33, id=48, name="VCO SAW SW"      },
  { path="vco_group,sqr_enc",   addr={0x10,0x00,0x08,0x09}, bits=7, sw=true, bcr=34, id=49, name="VCO SQR SW"      },
  { path="vco_group,sin_enc",   addr={0x10,0x00,0x08,0x0A}, bits=7, sw=true, bcr=35, id=50, name="VCO SIN SW"      },
  { path="vco_group,white_enc", addr={0x10,0x00,0x08,0x0B}, bits=7, sw=true, bcr=36, id=51, name="VCO WH NOISE SW" },
  { path="vco_group,pink_enc",  addr={0x10,0x00,0x08,0x0C}, bits=7, sw=true, bcr=37, id=52, name="VCO PK NOISE SW" },
  { path="vco_group,ring_enc",  addr={0x10,0x00,0x08,0x0D}, bits=7, sw=true, bcr=49, id=53, name="VCO RING SW"     },

  -- ========== VCF  10 00 0A 00 ==========
  -- vcf_cutoff and vcf_resonance are in panel_controls_group (F1 layout move)
  { path="panel_controls_group,vcf_cutoff_enc",    addr={0x10,0x00,0x0A,0x00}, bits=16, max=255, nrpn=5, id= 54, name="VCF CUTOFF"    },
  { path="panel_controls_group,vcf_resonance_enc", addr={0x10,0x00,0x0A,0x02}, bits=16, max=255, nrpn=6, id= 55, name="VCF RESONANCE" },
  { path="vcf_group,vcf_env_depth_enc",            addr={0x10,0x00,0x0A,0x04}, bits=16, max=255, nrpn=4, id= 56, name="VCF ENV DEPTH" },
  { path="vcf_group,vcf_attack_enc",               addr={0x10,0x00,0x0A,0x06}, bits=7,  bcr=90, id= 57, name="VCF ATTACK"    },
  { path="vcf_group,vcf_decay_enc",                addr={0x10,0x00,0x0A,0x07}, bits=7,  bcr=91, id= 58, name="VCF DECAY"     },
  { path="vcf_group,vcf_sustain_enc",              addr={0x10,0x00,0x0A,0x08}, bits=7,  bcr=92, id= 59, name="VCF SUSTAIN"   },
  { path="vcf_group,vcf_release_enc",              addr={0x10,0x00,0x0A,0x09}, bits=7,  bcr=93, id= 60, name="VCF RELEASE"   },
  { path="vcf_group,vcf_key_follow_enc",           addr={0x10,0x00,0x0A,0x0A}, bits=7, bcr=102, id= 61, name="VCF KEY FOLLOW"},

  -- ========== VCA  10 00 0C 00 ==========
  { path="vca_group,vca_attack_enc",   addr={0x10,0x00,0x0C,0x00}, bits=7, bcr=81, id=62, name="VCA ATTACK"  },
  { path="vca_group,vca_decay_enc",    addr={0x10,0x00,0x0C,0x01}, bits=7, bcr=82, id=63, name="VCA DECAY"   },
  { path="vca_group,vca_sustain_enc",  addr={0x10,0x00,0x0C,0x02}, bits=7, bcr=83, id=64, name="VCA SUSTAIN" },
  { path="vca_group,vca_release_enc",  addr={0x10,0x00,0x0C,0x03}, bits=7, bcr=84, id=65, name="VCA RELEASE" },
  -- patch_volume_enc moved to patch_group in F1 layout (same block 0C00)
  { path="patch_group,patch_volume_enc", addr={0x10,0x00,0x0C,0x04}, bits=7, bcr=89, id=66, name="MASTER VOLUME" },

  -- ========== DISTORTION  10 00 0E 00 ==========
  { path="dist_group,dist_on_off",        btn=true, addr={0x10,0x00,0x0E,0x00}, bits=7, bcr=71, id=67, name="DIST SW"       },
  -- dist_type: regSp → REGISTRY kind="sp" only (no enc); ENC_SEND_MAP still emitted
  { path="dist_group,dist_type_enc",      addr={0x10,0x00,0x0E,0x01}, bits=7, max=24, bcr=88, regSp="dist_type" },
  { path="dist_group,dist_drive_enc",     addr={0x10,0x00,0x0E,0x02}, bits=7, max=120,               bcr=87, id=69, name="DIST DRIVE"     },
  { path="dist_group,dist_bottom_enc",    addr={0x10,0x00,0x0E,0x03}, bits=7, max=100, bipolar=true, bcr=95, id=70, name="DIST BOTTOM"    },
  { path="dist_group,dist_tone_enc",      addr={0x10,0x00,0x0E,0x04}, bits=7, max=100, bipolar=true, bcr=96, id=71, name="DIST TONE"      },
  { path="dist_group,dist_efx_level_enc", addr={0x10,0x00,0x0E,0x05}, bits=7, max=100,              bcr=103, id=72, name="DIST EFX LEVEL" },
  { path="dist_group,dist_dry_level_enc", addr={0x10,0x00,0x0E,0x06}, bits=7, max=100,              bcr=104, id=73, name="DIST DRY LEVEL" },
  { path="dist_group,dist_color",         btn=true, addr={0x10,0x00,0x0E,0x07}, bits=7, bcr=79, id=74, name="DIST COLOR"    },

  -- ========== PORTAMENTO / PARAM ASSIGN  10 00 14 00 ==========
  -- porta_time_enc sw (PORTA SW) at off=0; enc (PORTA TIME) at off=1
  { path="portamento_group,porta_time_enc", sw=true, addr={0x10,0x00,0x14,0x00}, bits=7, id=254, name="PORTA SW"   },
  { path="portamento_group,porta_time_enc",           addr={0x10,0x00,0x14,0x01}, bits=7, id=255, name="PORTA TIME" },
  -- porta_mode: REGISTRY-only special (radio buttons, no path/id/bcr)
  { addr={0x10,0x00,0x14,0x02}, regSp="porta_mode" },
  { path="other_group,pitch_bend_range_enc", addr={0x10,0x00,0x14,0x03}, bits=7, max=23, semitoneRange=true, id=257, name="BENDER RANGE" },
  -- assign param-ID slots: REGISTRY-only u16 specials (no path/id/bcr)
  { addr={0x10,0x00,0x14,0x04}, regSp="assign_xy_mod",      regU16=true },
  { addr={0x10,0x00,0x14,0x06}, regSp="assign_effect_knob", regU16=true },
  { addr={0x10,0x00,0x14,0x08}, regSp="assign_pad_x",       regU16=true },
  { addr={0x10,0x00,0x14,0x0A}, regSp="assign_pad_y",       regU16=true },
  -- accent_level moved to panel_controls_group in F1 layout (same block 1400)
  { path="panel_controls_group,accent_level_enc", addr={0x10,0x00,0x14,0x0E}, bits=16, max=255, nrpn=7, id=264, name="ACCENT" },

}
