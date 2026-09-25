// SPDX-License-Identifier: AGPL-3.0-only
//
// The PMTiles v3 encoding (Hilbert tile ids, directory serialisation,
// header layout, root/leaf split) is adapted from protomaps/go-pmtiles
// (pmtiles/tile_id.go and pmtiles/directory.go, BSD-3-Clause, © 2021
// Protomaps LLC) for Alvyo on 2026-09-23, to avoid its cloud storage
// dependencies.

package packs

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"io"
)

// Tile types and compressions of the PMTiles v3 header.
const (
	tilePNG  = 2
	tileJPEG = 3

	compressionNone = 1
	compressionGzip = 2

	headerLen = 127
	// rootMaxLen keeps header and root directory within the first 16 KiB.
	rootMaxLen = 16384 - headerLen
)

// entry points at the data of a run of tiles with the same content.
type entry struct {
	tileID    uint64
	offset    uint64
	length    uint32
	runLength uint32
}

type header struct {
	rootOffset, rootLength         uint64
	metadataOffset, metadataLength uint64
	leafOffset, leafLength         uint64
	dataOffset, dataLength         uint64
	addressedTiles, tileEntries    uint64
	tileContents                   uint64
	tileType                       uint8
	minZoom, maxZoom               uint8
	minLonE7, minLatE7             int32
	maxLonE7, maxLatE7             int32
	centerZoom                     uint8
	centerLonE7, centerLatE7       int32
}

func rotate(n, x, y, rx, ry uint32) (uint32, uint32) {
	if ry == 0 {
		if rx != 0 {
			x, y = n-1-x, n-1-y
		}
		return y, x
	}
	return x, y
}

// tileID is the Hilbert curve id of tile z/x/y.
func tileID(z uint8, x, y uint32) uint64 {
	acc := (uint64(1)<<(z*2) - 1) / 3
	n := uint32(z) - 1
	for s := uint32(1) << n; s > 0; s >>= 1 {
		rx, ry := s&x, s&y
		acc += uint64((3*rx)^ry) << n
		x, y = rotate(s, x, y, rx, ry)
		n--
	}
	return acc
}

func serializeEntries(entries []entry) []byte {
	var b bytes.Buffer
	w, _ := gzip.NewWriterLevel(&b, gzip.BestCompression)
	tmp := make([]byte, binary.MaxVarintLen64)
	put := func(v uint64) { _, _ = w.Write(tmp[:binary.PutUvarint(tmp, v)]) }
	put(uint64(len(entries)))
	last := uint64(0)
	for _, e := range entries {
		put(e.tileID - last)
		last = e.tileID
	}
	for _, e := range entries {
		put(uint64(e.runLength))
	}
	for _, e := range entries {
		put(uint64(e.length))
	}
	for i, e := range entries {
		if i > 0 && e.offset == entries[i-1].offset+uint64(entries[i-1].length) {
			put(0)
		} else {
			put(e.offset + 1)
		}
	}
	_ = w.Close()
	return b.Bytes()
}

// directories serialises entries as a root directory, with leaf
// directories when they do not fit into the root.
func directories(entries []entry) (root, leaves []byte) {
	if len(entries) < 16384 {
		if r := serializeEntries(entries); len(r) <= rootMaxLen {
			return r, nil
		}
	}
	leafSize := max(len(entries)/3500, 4096)
	for {
		var rootEntries []entry
		leaves = leaves[:0]
		for i := 0; i < len(entries); i += leafSize {
			end := min(i+leafSize, len(entries))
			s := serializeEntries(entries[i:end])
			rootEntries = append(rootEntries, entry{tileID: entries[i].tileID, offset: uint64(len(leaves)), length: uint32(len(s))})
			leaves = append(leaves, s...)
		}
		if root = serializeEntries(rootEntries); len(root) <= rootMaxLen {
			return root, leaves
		}
		leafSize = leafSize * 6 / 5
	}
}

func (h header) bytes() []byte {
	b := make([]byte, headerLen)
	copy(b, "PMTiles")
	b[7] = 3
	le := binary.LittleEndian
	for i, v := range []uint64{h.rootOffset, h.rootLength, h.metadataOffset, h.metadataLength, h.leafOffset,
		h.leafLength, h.dataOffset, h.dataLength, h.addressedTiles, h.tileEntries, h.tileContents} {
		le.PutUint64(b[8+8*i:], v)
	}
	b[96] = 0 // not clustered: tile data is in download order
	b[97] = compressionGzip
	b[98] = compressionNone // JPEG and PNG are compressed already
	b[99] = h.tileType
	b[100], b[101] = h.minZoom, h.maxZoom
	le.PutUint32(b[102:], uint32(h.minLonE7))
	le.PutUint32(b[106:], uint32(h.minLatE7))
	le.PutUint32(b[110:], uint32(h.maxLonE7))
	le.PutUint32(b[114:], uint32(h.maxLatE7))
	b[118] = h.centerZoom
	le.PutUint32(b[119:], uint32(h.centerLonE7))
	le.PutUint32(b[123:], uint32(h.centerLatE7))
	return b
}

// writeArchive writes a PMTiles archive: header, root directory, metadata,
// leaf directories, then the tile data read from data.
func writeArchive(w io.Writer, h header, entries []entry, metadata []byte, data io.Reader) error {
	root, leaves := directories(entries)
	h.rootOffset, h.rootLength = headerLen, uint64(len(root))
	h.metadataOffset, h.metadataLength = h.rootOffset+h.rootLength, uint64(len(metadata))
	h.leafOffset, h.leafLength = h.metadataOffset+h.metadataLength, uint64(len(leaves))
	h.dataOffset = h.leafOffset + h.leafLength
	for _, part := range [][]byte{h.bytes(), root, metadata, leaves} {
		if _, err := w.Write(part); err != nil {
			return err
		}
	}
	_, err := io.Copy(w, data)
	return err
}

func gzipped(b []byte) []byte {
	var out bytes.Buffer
	w := gzip.NewWriter(&out)
	_, _ = w.Write(b)
	_ = w.Close()
	return out.Bytes()
}
