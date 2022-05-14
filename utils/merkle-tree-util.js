// Whole-script strict mode syntax
"use strict";

// Shamelessly adapted from OpenZeppelin-contracts test utils

const { keccak256, keccakFromString, bufferToHex } = require("ethereumjs-util");
const { hexToBytes } = require("./contract-util");

// Merkle tree called with 32 byte hex values
// 使用 32 字节十六进制值调用 Merkle 树
class MerkleTree {
  constructor(elements) {
    this.elements = elements
      .filter((el) => el)
      .map((el) => Buffer.from(hexToBytes(el)));

    // Sort elements
    //this.elements.sort(Buffer.compare);
    // Deduplicate elements
    //this.elements = this.bufDedup(this.elements);

    // 排序元素 this.elements.sort(Buffer.compare); 
    // 去重元素 this.elements = this.bufDedup(this.elements);

    // Create layers
    this.layers = this.getLayers(this.elements);
  }

  getLayers(elements) {
    if (elements.length === 0) {
      return [[""]];
    }

    const layers = [];
    layers.push(elements);
    
    // let reulsts = [];
    // let idx = [reulsts.length - 1];
    // let root = reulsts[idx];

    // Get next layer until we reach the root
    // 获取下一层，直到我们到达根
    while (layers[layers.length - 1].length > 1) {
      
      let nextLayer = this.getNextLayer(layers[layers.length - 1]);

      layers.push(nextLayer);
    }

    return layers;
  }

  getNextLayer(elements) {
    return elements.reduce((layer, el, idx, arr) => {
      if (idx % 2 === 0) {
        // 获取 当前元素及其 元素对 的 HASH值
        // Hash the current element with its pair element
        layer.push(this.combinedHash(el, arr[idx + 1]));

      }

      return layer;
    }, []);
  }

  // 组合
  combinedHash(first, second) {
    if (!first) {
      return second;
    }
    if (!second) {
      return first;
    }

    return keccak256(this.sortAndConcat(first, second));
  }

  getRoot() {
    return this.layers[this.layers.length - 1][0];
  }

  getHexRoot() {
    return bufferToHex(this.getRoot());
  }

  getProof(el) {
    let idx = this.bufIndexOf(el, this.elements);

    if (idx === -1) {
      throw new Error("Element does not exist in Merkle tree");
    }
    return this.layers.reduce((proof, layer) => {
      const pairElement = this.getPairElement(idx, layer);

      if (pairElement) {
        proof.push(pairElement);
      }

      idx = Math.floor(idx / 2);

      return proof;
    }, []);
  }

  // external call - convert to buffer
  // 外部调用 - 转换为缓冲区
  getHexProof(_el) {
    const el = Buffer.from(hexToBytes(_el));

    const proof = this.getProof(el);

    return this.bufArrToHexArr(proof);
  }

  getPairElement(idx, layer) {
    const pairIdx = idx % 2 === 0 ? idx + 1 : idx - 1;

    if (pairIdx < layer.length) {
      return layer[pairIdx];
    } else {
      return null;
    }
  }

  bufIndexOf(el, arr) {
    let hash;

    // Convert element to 32 byte hash if it is not one already
    // 如果元素还不是一个，则将元素转换为 32 字节散列
    if (el.length !== 32 || !Buffer.isBuffer(el)) {
      hash = keccakFromString(el);
    } else {
      hash = el;
    }

    for (let i = 0; i < arr.length; i++) {
      if (hash.equals(arr[i])) {
        return i;
      }
    }

    return -1;
  }

  bufDedup(elements) {
    return elements.filter((el, idx) => {
      return idx === 0 || !elements[idx - 1].equals(el);
    });
  }

  bufArrToHexArr(arr) {
    if (arr.some((el) => !Buffer.isBuffer(el))) {
      throw new Error("Array is not an array of buffers");
    }

    return arr.map((el) => "0x" + el.toString("hex"));
  }

  sortAndConcat(...args) {
    return Buffer.concat([...args].sort(Buffer.compare));
  }
}

module.exports = {
  MerkleTree,
};
