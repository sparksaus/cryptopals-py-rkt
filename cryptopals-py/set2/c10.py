# Challenge 10
## Implement CBC Mode

from Crypto.Cipher import AES
import sys
sys.path.insert(0, '../set1')
import c1, c2, c6, c9


### CBC Mode encryption  works by XORing the previous block with
### the plaintext before encrypting it.
### Ci = E(Pi ^ Ci-1)
def aes_128_cbc_encrypt(txt, key, IV='\x00'*16):
    # Assert all size constraints
    assert len(txt) % 16 == 0
    assert len(key) == 16
    assert len(IV) == 16
    num_blocks = len(txt) / 16
    prev_block = IV
    result = ''
    # Loop through each block, XORing with the previous
    for i in range(num_blocks):
        cur_block = c6.get_block(txt, i, 16)
        cur_block = c2.xorstrs(prev_block, cur_block)
        cur_block = AES.new(key, AES.MODE_ECB).encrypt(cur_block)
        prev_block = cur_block
        result += prev_block
    return result

### Decrypt works backwards
### Pi = D(Ci) ^ Ci-1
def aes_128_cbc_decrypt(txt, key, IV='\x00'*16):
    # Assert all size constrains
    assert len(txt) % 16 == 0
    assert len(key) == 16
    assert len(IV) == 16
    num_blocks = len(txt) / 16
    prev_block = IV
    result = ''
    # Loop through each block, XORing with the previous
    for i in range(num_blocks):
        cur_block = c6.get_block(txt, i, 16)
        temp = cur_block
        cur_block = AES.new(key, AES.MODE_ECB).decrypt(cur_block)
        cur_block = c2.xorstrs(cur_block, prev_block)
        prev_block = temp
        result += cur_block
    return result


def test():
    plaintext = 'Who lives in a pineapple under the sea?'
    plaintext = c9.pkcs7_pad(plaintext)
    key = 'YELLOW SUBMARINE'
    ciphertext = aes_128_cbc_encrypt(plaintext, key)
    pt = aes_128_cbc_decrypt(ciphertext, key)
    assert plaintext == pt, plaintext + '\n' + pt

def main():
    test()
    f = open('../../testdata/10.txt')
    ctxt = f.read()
    #ctxt = c9.pkcs7_pad(ctxt)
    key = 'YELLOW SUBMARINE'
    pt = aes_128_cbc_decrypt(c1.base64toascii(ctxt), key)
    print pt

if __name__ == '__main__' : main()